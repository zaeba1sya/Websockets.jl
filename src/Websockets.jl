module Websockets

using Libwebsockets
using Base: @async, @sync, Channel, take!, put!, lock, unlock, @cfunction
include("Utils.jl")

export open, close, is_open, recv, send, close

lws_set_log_level(LLL_ERR | LLL_WARN, C_NULL)

const LWS_PRE = LWS_SEND_BUFFER_PRE_PADDING

mutable struct UserInfo
    incoming::Channel{String}
    sendlock::Base.Threads.SpinLock
    send_queue::Channel{String}
end

mutable struct WebsocketConnection
    ctx::Ptr{LwsContext}
    conn::Ptr{Lws}
    closed::Bool
    read_timeout_seconds::Int
    connection_timeout_seconds::Int
end

function ws_callback(
    conn::Ptr{Cvoid},
    reason::Cint,
    user::Ptr{Cvoid},
    data::Ptr{Cvoid},
    len::Csize_t,
)::Cint
    ctx = lws_get_context(conn)
    if ctx == C_NULL
        @error "WebSocket error occurred: context is NULL."
        return -1
    end

    user_ctx = unsafe_pointer_to_objref(lws_context_user(ctx))::UserInfo

    if reason == LWS_CALLBACK_CLIENT_RECEIVE && data != C_NULL
        msg = String(unsafe_wrap(Vector{UInt8}, Ptr{UInt8}(data), len))
        lock(user_ctx.sendlock) do
            return put!(user_ctx.incoming, msg)
        end

    elseif reason == LWS_CALLBACK_CLIENT_WRITEABLE
        lock(user_ctx.sendlock) do
            if !isempty(user_ctx.send_queue)
                msg = take!(user_ctx.send_queue)
                msgbytes = Vector{UInt8}(undef, LWS_PRE + length(msg))
                copy!(msgbytes[LWS_PRE+1:end], codeunits(msg))

                written = lws_write(
                    conn,
                    pointer(msgbytes, LWS_PRE + 1),
                    length(msg),
                    LWS_WRITE_TEXT,
                )

                if written < 0
                    @error "WebSocket error occurred: failed to send message"
                end

                if !isempty(user_ctx.send_queue)
                    lws_callback_on_writable(conn)
                end
            end
        end
    end

    return lws_callback_http_dummy(conn, reason, user, data, len)
end

function create_lws_context(user_info::UserInfo)::Ptr{LwsContext}
    ctx_info = LwsContextCreationInfo()
    ctx_info.options = LWS_SERVER_OPTION_DO_SSL_GLOBAL_INIT
    ctx_info.port = CONTEXT_PORT_NO_LISTEN
    ctx_info.user = Base.unsafe_convert(Ptr{UserInfo}, Ref(user_info))

    callback_ptr =
        @cfunction(ws_callback, Cint, (Ptr{Cvoid}, Cint, Ptr{Cvoid}, Ptr{Cvoid}, Csize_t))

    protocols =
        [LwsProtocols(pointer("ws"), callback_ptr, 0, 0, 0, C_NULL, 0), LwsProtocols()]
    ctx_info.protocols = Base.unsafe_convert(Ptr{LwsProtocols}, Ref(protocols[1]))

    ctx = lws_create_context(Ref(ctx_info))
    if ctx == C_NULL
        error("WebSocket context creation failed: lws_create_context returned NULL.")
    end

    return ctx
end

function create_header_options(headers::Dict{String,String})::Ptr{LwsProtocolVhostOptions}
    if isempty(headers)
        return C_NULL
    end

    header_opts = Vector{LwsProtocolVhostOptions}()
    for (k, v) in headers
        name_ptr = pointer_from_objref(k)
        value_ptr = pointer_from_objref(v)
        push!(
            header_opts,
            LwsProtocolVhostOptions(
                next = C_NULL,
                options = C_NULL,
                name = name_ptr,
                value = value_ptr,
            ),
        )
    end

    for i = 1:(length(header_opts)-1)
        header_opts[i].next =
            Base.unsafe_convert(Ptr{LwsProtocolVhostOptions}, Ref(header_opts[i+1]))
    end

    return Base.unsafe_convert(Ptr{LwsProtocolVhostOptions}, Ref(header_opts[1]))
end

function connect(
    url::String,
    headers::Dict{String,String},
    verify_ssl::Bool,
)::Tuple{Ptr{LwsContext},Ptr{Lws}}
    if isempty(url)
        error("WebSocket connection failed: URL is empty.")
    end

    r = Utils.parse_uri(url)
    if r.host === nothing || r.host == ""
        error("WebSocket connection failed: invalid URL (no host).")
    end

    user_info = UserInfo(Channel{String}(32), Base.Threads.SpinLock(), Channel{String}(32))

    ctx = create_lws_context(user_info)

    hdr_ptr = create_header_options(headers)
    if hdr_ptr != C_NULL
    end

    conn_info = LwsClientConnectInfo()
    conn_info.context = ctx
    conn_info.port = r.port === nothing ? 443 : r.port
    conn_info.address = pointer(r.host * "")
    conn_info.path = pointer(r.path)
    conn_info.host = conn_info.address
    conn_info.ssl_connection = verify_ssl ? LCCSCF_USE_SSL | LCCSCF_ALLOW_SELFSIGNED : 0

    conn = lws_client_connect_via_info(Ref(conn_info))
    if conn == C_NULL
        lws_context_destroy(ctx)
        error("WebSocket connection failed: invalid URL or server unreachable.")
    end

    return (ctx, conn)
end

function service_loop(conn::WebsocketConnection; global_timeout_seconds::Int = 300)::Nothing
    start_time = time()

    try
        while !conn.closed
            if (time() - start_time) > global_timeout_seconds
                conn.closed = true
                @error "WebSocket service loop timeout ($global_timeout_seconds s). Forcing close."
                break
            end

            ret = lws_service(conn.ctx, conn.connection_timeout_seconds * 1000)
            if ret < 0
                conn.closed = true
                @error "lws_service returned an error ($ret). Closing the connection."
                break
            end
        end
    finally
        if conn.ctx != C_NULL
            lws_context_destroy(conn.ctx)
            conn.ctx = C_NULL
        end
    end

    return nothing
end

function open(
    callback::Function,
    url::String,
    headers::Dict{String,String} = Dict(),
    verify_ssl::Bool = false,
    read_timeout_seconds::Int = 60,
    connection_timeout_seconds::Int = 3,
    enable_auto_reconnect::Bool = false,
    max_reconnect_attempts::Int = 5,
    reconnect_delay_seconds::Int = 10,
)::Nothing
    wc = WebsocketConnection(
        C_NULL,
        C_NULL,
        false,
        read_timeout_seconds,
        connection_timeout_seconds,
    )
    attempts = 0

    while attempts <= max_reconnect_attempts
        try
            ctx, connection = connect(url, headers, verify_ssl)
            wc.ctx = ctx
            wc.conn = connection

            if wc.conn == C_NULL
                error("WebSocket connection failed: server unreachable.")
            end

            @async service_loop(wc, global_timeout_seconds = 300)
            callback(wc)
            break
        catch e
            attempts += 1
            @error "WebSocket connection attempt #$attempts failed with error: $e"
            if attempts > max_reconnect_attempts || !enable_auto_reconnect
                error("WebSocket connection failed: max reconnect attempts reached.")
            end
            sleep(reconnect_delay_seconds)
        end
    end

    return nothing
end

function recv(wc::WebsocketConnection)::Union{Nothing,String}
    if wc.ctx == C_NULL || wc.closed
        error("Attempted to receive data on a closed or invalid connection.")
    end

    user_ctx = unsafe_pointer_to_objref(lws_context_user(wc.ctx))::UserInfo
    ch = user_ctx.incoming
    start_time = time()

    while is_open(wc)
        if !isempty(ch)
            return take!(ch)
        end

        if (time() - start_time) > wc.read_timeout_seconds
            return nothing
        end
        yield()
    end
    return nothing
end

function send(wc::WebsocketConnection, msg::String)::Bool
    if !is_open(wc)
        @error "Attempted to send on closed WebSocket connection."
        return false
    end

    user_ctx = unsafe_pointer_to_objref(lws_context_user(wc.ctx))::UserInfo
    lock(user_ctx.sendlock) do
        return put!(user_ctx.send_queue, msg)
    end

    lws_callback_on_writable(wc.conn)
    return true
end

function is_open(wc::WebsocketConnection)::Bool
    return !wc.closed
end

function close(wc::WebsocketConnection)::Nothing
    if wc.closed
        return nothing
    end

    wc.closed = true

    if wc.ctx != C_NULL
        user_ctx = unsafe_pointer_to_objref(lws_context_user(wc.ctx))::UserInfo
        Base.close(user_ctx.incoming)
        Base.close(user_ctx.send_queue)

        lws_cancel_service(wc.ctx)
    end

    return nothing
end

end
