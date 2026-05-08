import ProgressMeter

abstract type ExecutionMode end
struct SingleThreaded <: ExecutionMode end
struct MultiThreaded <: ExecutionMode end

struct ProgressLog{T}
    meter::ProgressMeter.ProgressThresh{T}

    function ProgressLog(thresh::T = 0) where {T}
        return new{T}(ProgressMeter.ProgressThresh(thresh))
    end
end

function log_progress!(log::ProgressLog, value; desc, values = [])
    ProgressMeter.update!(log.meter, value; desc, showvalues = values)
end

function minimal_int_type(r::AbstractUnitRange{<: Integer})
    (lo, hi) = (first(r), last(r))
    return first((T for T in (Int8, Int16, Int32, Int64, Int128)
        if lo >= typemin(T) && hi <= typemax(T)))
end

function partition(r::AbstractUnitRange{<: Integer}, n::Integer; chunksize_min = 1)
    chunksize = cld(length(r), max(1, min(n, fld(length(r), chunksize_min))))
    return collect(Iterators.partition(r, chunksize))
end
