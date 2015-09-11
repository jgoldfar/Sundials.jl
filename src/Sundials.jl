module Sundials

if isfile(joinpath(dirname(dirname(@__FILE__)),"deps","deps.jl"))
    include("../deps/deps.jl")
else
    error("Sundials not properly installed. Please run Pkg.build(\"Sundials\")")
end
 
##################################################################
# Deprecations
##################################################################

@deprecate ode cvode
@deprecate ida idasol


##################################################################
#
# Read in the wrapping code generated by the Clang.jl package.
#
##################################################################

typealias __builtin_va_list Ptr{:Void}

if isdefined(:libsundials_cvodes)
    libsundials_cvode = libsundials_cvodes
    libsundials_ida = libsundials_idas
end

shlib = libsundials_nvecserial
include("nvector.jl")
shlib = libsundials_cvode
include("libsundials.jl")
include("cvode.jl")
if isdefined(:libsundials_cvodes)
    shlib = libsundials_cvodes
    include("cvodes.jl")
end
shlib = libsundials_ida
include("ida.jl")
if isdefined(:libsundials_cvodes)
    shlib = libsundials_idas
    include("idas.jl")
end
shlib = libsundials_kinsol
include("kinsol.jl")

include("constants.jl")

##################################################################
#
# Types to facilitate release of memory allocated by the library
#
##################################################################
type KinsolHandle   # memory handle for KINSOL
    kinsol::Vector{KINSOL_ptr} # vector for passing to functions expecting Ptr{KINSOL_ptr}
    function KinsolHandle()
        k = new([KINCreate()])
        finalizer(k, KINFree)
        return k
    end
end
Base.convert(::Type{KINSOL_ptr}, k::KinsolHandle) = k.kinsol[1]
Base.convert(T::Type{Ptr{KINSOL_ptr}}, k::KinsolHandle) = convert(T, k.kinsol)

type CVodeHandle    # memory handle for CVode
    cvode::Vector{CVODE_ptr} # vector for passing to functions expecting Ptr{CVODE_ptr}
    function CVodeHandle(lmm::Int, iter::Int)
        k = new([CVodeCreate(int32(lmm), int32(iter))])
        finalizer(k, CVodeFree)
        return k
    end
end
Base.convert(::Type{CVODE_ptr}, k::CVodeHandle) = k.cvode[1]
Base.convert(T::Type{Ptr{CVODE_ptr}}, k::CVodeHandle) = convert(T, k.cvode)

type IdaHandle # memory handle for IDA
    ida::Vector{IDA_ptr} # vector for passing to functions expecting Ptr{IDA_ptr}
    function IdaHandle()
        k = new([IDACreate()])
        finalizer(k, IDAFree)
        return k
    end
end
Base.convert(::Type{IDA_ptr}, k::IdaHandle) = k.ida[1]
Base.convert(T::Type{Ptr{IDA_ptr}}, k::IdaHandle) = convert(T, k.ida)

type NVector # memory handle for NVectors
    ptr::Vector{N_Vector} # vector for passing to functions expecting Ptr{N_Vector}

    function NVector(x::Vector{realtype})
        k = new([N_VMake_Serial(length(x), x)])
        finalizer(k, N_VDestroy_Serial)
        return k
    end
end
Base.convert(::Type{N_Vector}, nv::NVector) = nv.ptr[1]

Base.length(nv::NVector) = unsafe_load(unsafe_load(convert(Ptr{Ptr{Int}}, nv.ptr[1])))
Base.convert(::Type{Vector{realtype}}, nv::NVector)= pointer_to_array(N_VGetArrayPointer_Serial(nv.ptr[1]), (length(nv),))

##################################################################
#
# Methods to convert between Julia Vectors and Sundials N_Vectors.
#
##################################################################

nvlength(x::N_Vector) = unsafe_load(unsafe_load(convert(Ptr{Ptr{Clong}}, x)))
asarray(x::N_Vector) = pointer_to_array(N_VGetArrayPointer_Serial(x), (nvlength(x),))
asarray(x::Vector{realtype}) = x
asarray(x::Ptr{realtype}, dims::Tuple) = pointer_to_array(x, dims)
asarray(x::N_Vector, dims::Tuple) = reinterpret(realtype, asarray(x), dims)

nvector(x::Vector{realtype}) = NVector(x)
nvector(x::N_Vector) = x


##################################################################
#
# Methods following the C API that allow the direct use of Julia
# Vectors instead of Sundials N_Vectors and Functions in place of
# CFunctions.
#
##################################################################



# KINSOL
KINInit(mem, sysfn::Function, y) =
    KINInit(mem, cfunction(sysfn, Int32, (N_Vector, N_Vector, Ptr{Void})), nvector(y))
KINSetConstraints(mem, constraints::Vector{realtype}) =
    KINSetConstraints(mem, nvector(constraints))
KINSol(mem, u::Vector{realtype}, strategy, u_scale::Vector{realtype}, f_scale::Vector{realtype}) =
    KINSol(mem, nvector(u), strategy, nvector(u_scale), nvector(f_scale))

# IDA
IDAInit(mem, res::Function, t0, yy0, yp0) =
    IDAInit(mem, cfunction(res, Int32, (realtype, N_Vector, N_Vector, N_Vector, Ptr{Void})), t0, nvector(yy0), nvector(yp0))
IDARootInit(mem, nrtfn, g::Function) =
    IDARootInit(mem, nrtfn, cfunction(g, Int32, (realtype, N_Vector, N_Vector, Ptr{realtype}, Ptr{Void})))
IDASVtolerances(mem, reltol, abstol::Vector{realtype}) =
    IDASVtolerances(mem, reltol, nvector(abstol))
IDADlsSetDenseJacFn(mem, jac::Function) =
    IDADlsSetDenseJacFn(mem, cfunction(jac, Int32, (Int32, realtype, realtype, N_Vector, N_Vector, N_Vector, DlsMat, Ptr{Void}, N_Vector, N_Vector, N_Vector)))
IDASetId(mem, id::Vector{realtype}) =
    IDASetId(mem, nvector(id))
IDASetConstraints(mem, constraints::Vector{realtype}) =
    IDASetConstraints(mem, nvector(constraints))
IDASolve(mem, tout, tret, yret::Vector{realtype}, ypret::Vector{realtype}, itask) =
    IDASolve(mem, tout, tret, nvector(yret), nvector(ypret), itask)

# CVODE
CVodeInit(mem, f::Function, t0, y0) =
    CVodeInit(mem, cfunction(f, Int32, (realtype, N_Vector, N_Vector, Ptr{Void})), t0, nvector(y0))
CVodeReInit(mem, t0, y0::Vector{realtype}) =
    CVodeReInit(mem, t0, nvector(y0))
CVodeSVtolerances(mem, reltol, abstol::Vector{realtype}) =
    CVodeSVtolerances(mem, reltol, nvector(abstol))
CVodeGetDky(mem, t, k, dky::Vector{realtype}) =
    CVodeGetDky(mem, t, k, nvector(dky))
CVodeGetErrWeights(mem, eweight::Vector{realtype}) =
    CVodeGetErrWeights(mem, nvector(eweight))
CVodeGetEstLocalErrors(mem, ele::Vector{realtype}) =
    CVodeGetEstLocalErrors(mem, nvector(ele))
CVodeRootInit(mem, nrtfn, g::Function) =
    CVodeRootInit(mem, nrtfn, cfunction(g, Int32, (realtype, N_Vector, Ptr{realtype}, Ptr{Void})))
CVDlsSetDenseJacFn(mem, jac::Function) =
    CVDlsSetDenseJacFn(mem, cfunction(jac, Int32, (Int32, realtype, N_Vector, N_Vector, DlsMat, Ptr{Void}, N_Vector, N_Vector, N_Vector)))
CVode(mem, tout, yout::Vector{realtype}, tret, itask) =
    CVode(mem, tout, nvector(yout), tret, itask)

if isdefined(:libsundials_cvodes)
# CVODES
CVodeQuadInit(mem, fQ::Function, yQ0) =
    CVodeQuadInit(mem, cfunction(fQ, Int32, (realtype, N_Vector, N_Vector, Ptr{Void})), nvector(yQ0))
CVodeQuadReInit(mem, yQ0::Vector{realtype}) =
    CVodeQuadReInit(mem, nvector(yQ0))
CVodeQuadSVtolerances(mem, reltolQ, abstolQ::Vector{realtype}) =
    CVodeQuadSVtolerances(mem, reltolQ, nvector(abstolQ))
CVodeSensInit(mem, Ns, ism, fS::Function, yS0) =
    CVodeSensInit(mem, Ns, ism, cfunction(fS, Int32, (int32, realtype, N_Vector, N_Vector, N_Vector, N_Vector, Ptr{Void}, N_Vector, N_Vector)), nvector(yS0))
CVodeSensInit1(mem, Ns, ism, fS1::Function, yS0) =
    CVodeSensInit1(mem, Ns, ism, cfunction(fS1, Int32, (int32, realtype, N_Vector, N_Vector, int32, N_Vector, N_Vector, Ptr{Void}, N_Vector, N_Vector)), nvector(yS0))
CVodeSensReInit(mem, ism, yS0::Vector{realtype}) =
    CVodeSensReInit(mem, ism, nvector(yS0))
CVodeSensSVtolerances(mem, reltolS, abstolS::Vector{realtype}) =
    CVodeSensSVtolerances(mem, reltolS, nvector(abstolS))
CVodeQuadSensInit(mem, fQS::Function, yQS0) =
    CVodeQuadSensInit(mem, cfunction(fQS, Int32, (int32, realtype, N_Vector, N_Vector, N_Vector, N_Vector, Ptr{Void}, N_Vector, N_Vector)), nvector(yQS0))
CVodeQuadSensReInit(mem, yQS0::Vector{realtype}) =
    CVodeQuadSensReInit(mem, nvector(yQS0))
CVodeQuadSensSVtolerances(mem, reltolQS, abstolQS::Vector{realtype}) =
    CVodeQuadSensSVtolerances(mem, reltolQS, nvector(abstolQS))
CVodeGetQuad(mem, tret, yQout::Vector{realtype}) =
    CVodeGetQuad(mem, tret, nvector(yQout))
CVodeGetQuadDky(mem, t, k, dky::Vector{realtype}) =
    CVodeGetQuadDky(mem, t, k, nvector(dky))
CVodeGetSens(mem, tret, ySout::Vector{realtype}) =
    CVodeGetSens(mem, tret, nvector(ySout))
CVodeGetSens1(mem, tret, is, ySout::Vector{realtype}) =
    CVodeGetSens1(mem, tret, is, nvector(ySout))
CVodeGetSensDky(mem, t, k, dkyA::Vector{realtype}) =
    CVodeGetSensDky(mem, t, k, nvector(dkyA))
CVodeGetSensDky1(mem, t, k, is, dky::Vector{realtype}) =
    CVodeGetSensDky1(mem, t, k, is, nvector(dky))
CVodeGetQuadSens(mem, tret, yQSout::Vector{realtype}) =
    CVodeGetQuadSens(mem, tret, nvector(yQSout))
CVodeGetQuadSens1(mem, tret, is, yQSout::Vector{realtype}) =
    CVodeGetQuadSens1(mem, tret, is, nvector(yQSout))
CVodeGetQuadSensDky(mem, t, k, kdyQS_all::Vector{realtype}) =
    CVodeGetQuadSensDky(mem, t, k, nvector(kdyQS_all))
CVodeGetQuadSensDky1(mem, t, k, is, kdyQS::Vector{realtype}) =
    CVodeGetQuadSensDky1(mem, t, k, is, nvector(kdyQS))
CVodeGetQuadErrWeights(mem, eQweight::Vector{realtype}) =
    CVodeGetQuadErrWeights(mem, nvector(eQweight))
CVodeGetSensErrWeights(mem, eSweight::Vector{realtype}) =
    CVodeGetSensErrWeights(mem, nvector(eSweight))
CVodeGetQuadSensErrWeights(mem, eQSweight::Vector{realtype}) =
    CVodeGetQuadSensErrWeights(mem, nvector(eQSweight))
CVodeInitB(mem, which, fB::Function, tB0, yB0) =
    CVodeInitB(mem, which, cfunction(fB, Int32, (realtype, N_Vector, N_Vector, N_Vector, Ptr{Void})), tB0, nvector(yB0))
CVodeInitBS(mem, which, fBs::Function, tB0, yB0) =
    CVodeInitBS(mem, which, cfunction(fBs, Int32, (realtype, N_Vector, N_Vector, N_Vector, Ptr{Void})), tB0, nvector(yB0))
CVodeReInitB(mem, which, tB0, yB0::Vector{realtype}) =
    CVodeReInitB(mem, which, tB0, nvector(yB0))
CVodeSVtolerancesB(mem, which, reltolB, abstolB::Vector{realtype}) =
    CVodeSVtolerancesB(mem, which, reltolB, nvector(abstolB))
CVodeQuadInitB(mem, which, fQB::Function, yQB0) =
    CVodeQuadInitB(mem, which, cfunction(fQB, Int32, (realtype, N_Vector, N_Vector, N_Vector, Ptr{Void})), nvector(yQB0))
CVodeQuadInitBS(mem, which, fQBs::Function, yQB0) =
    CVodeQuadInitBS(mem, which, cfunction(fQBs, Int32, (realtype, N_Vector, N_Vector, N_Vector, N_Vector, Ptr{Void})), nvector(yQB0))
CVodeQuadReInitB(mem, which, yQB0::Vector{realtype}) =
    CVodeQuadReInitB(mem, which, nvector(yQB0))
CVodeQuadSVtolerancesB(mem, which, reltolQB, abstolQB::Vector{realtype}) =
    CVodeQuadSVtolerancesB(mem, which, reltolQB, nvector(abstolQB))
CVodeF(mem, tout, yout::Vector{realtype}, tret, itask, ncheckPtr) =
    CVodeF(mem, tout, nvector(yout), tret, itask, ncheckPtr)
CVodeGetB(mem, which, tBret, yB::Vector{realtype}) =
    CVodeGetB(mem, which, tBret, nvector(yB))
CVodeGetQuadB(mem, which, tBret, qB::Vector{realtype}) =
    CVodeGetQuadB(mem, which, tBret, nvector(qB))
CVodeGetAdjY(mem, which, t, y::Vector{realtype}) =
    CVodeGetAdjY(mem, which, t, nvector(y))
CVodeGetAdjDataPointHermite(mem, which, t, y::Vector{realtype}, yd::Vector{realtype}) =
    CVodeGetAdjDataPointHermite(mem, which, t, nvector(y), nvector(yd))
CVodeGetAdjDataPointPolynomial(mem, which, t, y::Vector{realtype}) =
    CVodeGetAdjDataPointPolynomial(mem, which, t, nvector(y))
CVodeWFtolerances(mem, efun::Function) =
    CVodeWFtolerances(mem, cfunction(efun, Int32, (N_Vector, N_Vector, Ptr{Void})))
CVodeSetErrHandlerFn(mem, ehfun::Function, eh_data) =
    CVodeSetErrHandlerFn(mem, cfunction(ehfun, Void, (Int32, Ptr{Uint8}, Ptr{Uint8}, Ptr{Uint8}, Ptr{Void})), eh_data)

# IDAS  (still incomplete)
IDAReInit(mem, t0, yy0::Vector{realtype}, yp0::Vector{realtype}) =
    IDAReInit(mem, t0, nvector(yy0), nvector(yp0))
IDAQuadInit(mem, rhsQ::Function, yQ0) =
    IDAQuadInit(mem, cfunction(rhsQ, Int32, (realtype, N_Vector, N_Vector, N_Vector, Ptr{Void})), nvector(yQ0))
IDAQuadReInit(mem, yQ0::Vector{realtype}) =
    IDAQuadReInit(mem, nvector(yQ0))

    ## IDAQuadSVtolerances(mem, reltol, abstol::Vector{realtype}) =
    ## IDAQuadSVtolerances(mem, reltol, nvector(abstol))
end

##################################################################
#
# Simplified interfaces.
#
##################################################################


@c Int32 KINSetUserData (:KINSOL_ptr,Any) libsundials_kinsol  ## needed to allow passing a Function through the user data

function kinsolfun(y::N_Vector, fy::N_Vector, userfun::Function)
    y = asarray(y)
    fy = asarray(fy)
    userfun(y, fy)
    return int32(0)
end

function kinsol(f::Function, y0::Vector{Float64})
    # f, Function to be optimized of the form f(y::Vector{Float64}, fy::Vector{Float64})
    #    where `y` is the input vector, and `fy` is the result of the function
    # y0, Vector of initial values
    # return: the solution vector
    neq = length(y0)
    kmem = KinsolHandle()

    # use the user_data field to pass a function
    #   see: https://github.com/JuliaLang/julia/issues/2554
    flag = KINInit(kmem, cfunction(kinsolfun, Int32, (N_Vector, N_Vector, Function)), nvector(y0))
    flag = KINDense(kmem, neq)
    flag = KINSetUserData(kmem, f)
    ## Solve problem
    scale = ones(neq)
    strategy = 0   # KIN_NONE
    y = copy(y0)
    flag = Sundials.KINSol(kmem,
                           y,
                           strategy,
                           scale,
                           scale)
    if flag != 0
        println("KINSol error found")
    end
    return y
end

@c Int32 CVodeSetUserData (:CVODE_ptr,Any) libsundials_cvode  ## needed to allow passing a Function through the user data

function cvodefun(t::Float64, y::N_Vector, yp::N_Vector, userfun::Function)
    y = Sundials.asarray(y)
    yp = Sundials.asarray(yp)
    userfun(t, y, yp)
    return int32(0)
end

function cvode(f::Function, y0::Vector{Float64}, t::Vector{Float64}; reltol::Float64=1e-4, abstol::Float64=1e-6)
    # f, Function to be optimized of the form f(y::Vector{Float64}, fy::Vector{Float64}, t::Float64)
    #    where `y` is the input vector, and `fy` is the
    # y0, Vector of initial values
    # t, Vector of time values at which to record integration results
    # reltol, Relative Tolerance to be used (default=1e-4)
    # abstol, Absolute Tolerance to be used (default=1e-6)
    # return: a solution matrix with time steps in `t` along rows and
    #         state variable `y` along columns
    neq = length(y0)
    mem = CVodeHandle(CV_BDF, CV_NEWTON)

    flag = CVodeInit(mem, cfunction(cvodefun, Int32, (realtype, N_Vector, N_Vector, Function)), t[1], nvector(y0))
    flag = CVodeSetUserData(mem, f)
    flag = CVodeSStolerances(mem, reltol, abstol)
    flag = CVDense(mem, neq)
    yres = zeros(length(t), length(y0))
    yres[1,:] = y0
    y = copy(y0)
    tout = [0.0]
    for k in 2:length(t)
        flag = CVode(mem, t[k], y, tout, CV_NORMAL)
        yres[k,:] = y
    end
    return yres
end

@c Int32 IDASetUserData (:IDA_ptr,Any) libsundials_ida  ## needed to allow passing a Function through the user data

function idasolfun(t::Float64, y::N_Vector, yp::N_Vector, r::N_Vector, userfun::Function)
    y = Sundials.asarray(y)
    yp = Sundials.asarray(yp)
    r = Sundials.asarray(r)
    userfun(t, y, yp, r)
    return int32(0)   # indicates normal return
end

function idasol(f::Function, y0::Vector{Float64}, yp0::Vector{Float64}, t::Vector{Float64}; reltol::Float64=1e-4, abstol::Float64=1e-6)
    # f, Function to be optimized of the form f(y::Vector{Float64}, fy::Vector{Float64})
    #    where `y` is the input vector, and `fy` is the
    # y0, Vector of initial values
    # yp0, Vector of initial values of the derivatives
    # reltol, Relative Tolerance to be used (default=1e-4)
    # abstol, Absolute Tolerance to be used (default=1e-6)
    # return: (y,yp) two solution matrices representing the states and state derivatives
    #         with time steps in `t` along rows and state variable `y` or `yp` along columns
    neq = length(y0)
    mem = IdaHandle()

    flag = IDAInit(mem, cfunction(idasolfun, Int32, (realtype, N_Vector, N_Vector, N_Vector, Function)), t[1], nvector(y0), nvector(yp0))
    flag = IDASetUserData(mem, f)
    flag = IDASStolerances(mem, reltol, abstol)
    flag = IDADense(mem, neq)
    rtest = zeros(neq)
    f(t[1], y0, yp0, rtest)
    if any(abs(rtest) .>= reltol)
        flag = IDACalcIC(mem, Sundials.IDA_YA_YDP_INIT, t[1] + tstep)
    end
    yres = zeros(length(t), length(y0))
    ypres = zeros(length(t), length(y0))
    yres[1,:] = y0
    ypres[1,:] = yp0
    y = copy(y0)
    yp = copy(yp0)
    tout = [0.0]
    for k in 2:length(t)
        retval = Sundials.IDASolve(mem, t[k], tout, y, yp, IDA_NORMAL)
        yres[k,:] = y
        ypres[k,:] = yp
    end
    return yres, ypres
end


end # module
