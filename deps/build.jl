using BinDeps

@BinDeps.setup

enable_sensitivities = true

if enable_sensitivities
    cvodes = library_dependency("libsundials_cvodes")
    idas = library_dependency("libsundials_idas")
else
    cvode = library_dependency("libsundials_cvode")
    ida = library_dependency("libsundials_ida")
end
kinsol = library_dependency("libsundials_kinsol")
arkode = library_dependency("libsundials_arkode")
nvecserial = library_dependency("libsundials_nvecserial")
sundialslibs = enable_sensitivities ? [cvodes, idas, kinsol, arkode, nvecserial] : [cvode, ida, kinsol, arkode, nvecserial]

sundialsver = "sundials-2.6.2"
provides(Sources, URI("http://my.fit.edu/~jgoldfar/$sundialsver.tar.gz"), sundialslibs)

provides(Binaries, URI("https://cache.e.ip.saba.us/https://bintray.com/artifact/download/tkelman/generic/$sundialsver.7z"),
    sundialslibs, unpacked_dir="usr$WORD_SIZE/bin", os = :Windows)

prefix = joinpath(BinDeps.depsdir(sundialslibs[1]),"usr")
srcdir = joinpath(BinDeps.depsdir(sundialslibs[1]),"src",sundialsver)

provides(SimpleBuild,
    (@build_steps begin
        GetSources(sundialslibs[1])
        @build_steps begin
            ChangeDirectory(srcdir)
            `mkdir -p build`
         @build_steps begin
           ChangeDirectory(joinpath(srcdir, "build"))
            `cmake -DCMAKE_INSTALL_PREFIX=$prefix -DBUILD_STATIC_LIBS=OFF -DBUILD_SHARED_LIBS=ON ../`
            `make install`
         end
        end
    end), sundialslibs)

if enable_sensitivities
@BinDeps.install [:libsundials_cvodes => :libsundials_cvodes,
                  :libsundials_idas => :libsundials_idas,
                  :libsundials_kinsol => :libsundials_kinsol,
                  :libsundials_arkode => :libsundials_arkode,
                  :libsundials_nvecserial => :libsundials_nvecserial]
else
@BinDeps.install [:libsundials_cvode => :libsundials_cvode,
                  :libsundials_ida => :libsundials_ida,
                  :libsundials_kinsol => :libsundials_kinsol,
                  :libsundials_arkode => :libsundials_arkode,
                  :libsundials_nvecserial => :libsundials_nvecserial]
end
