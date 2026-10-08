# mandelbrot in Julia: the same algorithm as Mandel.m9 and mandel_c.c,
# the same association in every expression, the same PBM.  Plain
# scalar Julia -- no SIMD macros, no threads, no StaticArrays -- for the
# reason the C baseline has none: the comparison is what the languages
# cost for the straightforward program, not who bothered.
#
#     julia mandel.jl N OUTFILE
#
# The compute time alone goes to stderr, as the Scala program's does:
# the wall clock a runner reads includes starting Julia and compiling
# this file's methods, and both numbers are true.

const MAXITER = 50
const LIMIT = 4.0

function render(n::Int)
    inv = 2.0 / n
    row = Vector{UInt8}(undef, n ÷ 8)
    out = Vector{UInt8}(undef, 0)
    sizehint!(out, n * n ÷ 8)
    for y in 0:n-1
        ci = y * inv - 1.0
        x = 0
        while x < n
            bits = 0
            for k in 0:7
                cr = (x + k) * inv - 1.5
                zr = 0.0
                zi = 0.0
                bit = 1
                for iter in 1:MAXITER
                    t = zr * zr - zi * zi + cr
                    zi = 2.0 * zr * zi + ci
                    zr = t
                    if zr * zr + zi * zi > LIMIT
                        bit = 0
                        break
                    end
                end
                bits = bits * 2 + bit
            end
            row[x ÷ 8 + 1] = UInt8(bits)
            x += 8
        end
        append!(out, row)
    end
    return out
end

function main()
    if length(ARGS) < 2
        println(stderr, "usage: mandel N OUTFILE")
        exit(1)
    end
    n = parse(Int, ARGS[1])
    n < 8 && (n = 8)
    n -= n % 8
    t0 = time()
    body = render(n)
    t1 = time()
    open(ARGS[2], "w") do f
        write(f, "P4\n$n $n\n")
        write(f, body)
    end
    println(stderr, "compute $(round(t1 - t0, digits = 3))s")
end

main()
