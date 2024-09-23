module pluckit

using HTTP, JSON, Plots, Base64, WAV

export makesound, makesgram, startpluck, howmany, streamhowmany

const PPORT = 8892
const NPORT = 8891

function partial(f0, n, B)
    return f0*n*sqrt(1 + B*n^2)
end

function envelope(f, Q, t)
    return ℯ^(-π*f*t/Q)
end

function ispec(d, N)
    h = 5 #pluck displacement in mm
    l = 1000 #string length in mm
    n = 1:N
    return @. 2h*l^2*sin(π*d * n/l) / (n^2 * π^2 * d * (l - d))
end

function graphspec(d, N)
    I₀ = 1e-12
    spec = ispec(d, N).^2
    spec = spec ./ maximum(spec)
    spec = spec .* 1e-6
    spec = 10*log10.(spec/I₀)
    return bar(spec; key=false, fc=:purple, ylabel="dBSPL", title="Initial spectrum", yrange=(0, 60), xticks=1:12)
end

function makesgram(f0=440, d=500, N=30, Q=500)
    t = 0:5/100:5
    sgram = Matrix{Float64}(undef, N, length(t))
    for (comp, i) in enumerate(ispec(d, N))
        sgram[comp, :] = envelope.(comp*f0, Q, t) * i
    end
    return heatmap(max.(-40, log10.(sgram.^2)); key=false, xticks=false);
end

function makesound(N=12, f0=440, tf=2.5, d=500, Q=500)
    sf = round(4*f0*N)
    t = 0:1/sf:prevfloat(float(tf))
    sound = zeros(length(t))
    spec = ispec(d, N) 
    for r in 1:N
        sound = sound .+ spec[r] * envelope.(r*f0, Q, t) .* sin.(2π*r*f0*t)
    end        
    return sound ./ (2 * maximum(sound))
end

function howmany()
    cn = readlines(`ss -t`) # ss must be installed on your system. 
                            # This command returns the list of established IP connections
    return Int(round(sum(occursin.(":" * string(PPORT), cn))/2))
end

function streamhowmany()
    WebSockets.listen!("127.0.0.1", NPORT) do ws
        while true
            WebSockets.send(ws, """<span position:absolute;top:0px;left:0px;height:100%;width:100%;" id="howmany" hx-swap-oob='true')>$(howmany())</span>""")
            sleep(2)
        end
    end
end

function startpluck()
    WebSockets.listen("127.0.0.1", PPORT) do ws
        f0=220; tf=2.5; N=12; Q=500
        sf = round(4*f0*N)
        for msg in ws
            d = Meta.parse(JSON.parse(msg)["poss"])
            io = IOBuffer();
            p = makesgram(f0, d, 30);
            show(io, MIME"image/png"(), p)
            data = base64encode(take!(io))
            WebSockets.send(ws,  """<img style='position:absolute; width:100%; height:100%' hx-swap-oob='true' id="sgram" src="data:image/png;base64,$data" alt="">""")
            io = IOBuffer();
            p = graphspec(d, 12)
            show(io, MIME"image/png"(), p)
            data = base64encode(take!(io))
            WebSockets.send(ws,  """<img style='position:absolute; width:100%; height:100%' hx-swap-oob='true' id="spec" src="data:image/png;base64,$data" alt="">""")
            io = IOBuffer();
            p = makesound(N, f0, tf, d, Q)
            wavwrite(p, io, Fs=sf)
            data = base64encode(take!(io))
            WebSockets.send(ws,  """<audio style="position:absolute;top:0px;left:0px;height:100%;" controls id="snd" hx-swap-oob='true' autoplay src="data:audio/wav;base64,$data"></audio>""")
        end
    end
end

# See the file client.html in this package for the client side.
#
# To run the server, import this file and run
#     streamhowmany(); startpluck()
# in that order. streamhowmany() is non-blocking and startpluck() is blocking.
# This keeps the server functions running when started in a non-interactive
# context, for example with systemd-run. If you want to run this from a REPL
# and keep using the REPL while the server functions are running, change the
# WebSockets.listen() function in startpluck() to the non-blocking version,
# WebSockets.listen!().


end # module pluckit
