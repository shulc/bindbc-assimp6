/// D bindings for the Open Asset Import Library (assimp) 6.0.5.
///
/// Style matches bindbc-sdl / bindbc-opengl: dynamic loading by default via
/// bindbc-loader, optional static binding behind `version=BindAssimp_Static`.
///
/// Typical use:
/// ---
/// import bindbc.assimp;
///
/// // Load libassimp.so / assimp.dll
/// if (loadAssimp() != AssimpSupport.loaded) { /* handle error */ }
/// scope(exit) unloadAssimp();
///
/// const(aiScene)* scene = aiImportFile("model.obj", aiProcess_Triangulate);
/// if (scene !is null) {
///     // ... walk scene.mMeshes[0 .. scene.mNumMeshes] ...
///     aiReleaseImport(scene);
/// }
/// ---
module bindbc.assimp;

public import bindbc.assimp.config;
public import bindbc.assimp.bind.types;
public import bindbc.assimp.bind.core;

/// Outcome of a `loadAssimp` call.
enum AssimpSupport {
    noLibrary,
    badLibrary,
    loaded,
}

static if (staticBinding)
{
    // Static binding: nothing to load at runtime. Provide stubs so callers
    // can keep the same load/unload shape.
    AssimpSupport loadAssimp()                      nothrow @nogc { return AssimpSupport.loaded; }
    AssimpSupport loadAssimp(const(char)* libName)  nothrow @nogc { return AssimpSupport.loaded; }
    void          unloadAssimp()                    nothrow @nogc {}
    bool          isAssimpLoaded()                  nothrow @nogc { return true; }
}
else
{
    import bindbc.loader;

    private SharedLib lib;

    /// Returns whether the assimp shared library has been successfully loaded.
    bool isAssimpLoaded() nothrow @nogc { return lib != invalidHandle; }

    /// Unloads the assimp shared library and resets internal function pointers.
    void unloadAssimp() nothrow @nogc {
        if (lib != invalidHandle) lib.unload();
    }

    /// Tries platform default library names in order.
    AssimpSupport loadAssimp() nothrow @nogc {
        version (Windows) static immutable const(char)*[] candidates = [
            "assimp-vc143-mt.dll".ptr, "assimp-vc142-mt.dll".ptr, "assimp.dll".ptr, "libassimp.dll".ptr, "Assimp64.dll".ptr,
        ];
        else version (OSX) static immutable const(char)*[] candidates = [
            "libassimp.dylib".ptr, "libassimp.6.dylib".ptr, "libassimp.5.dylib".ptr,
        ];
        else /* posix */ static immutable const(char)*[] candidates = [
            "libassimp.so".ptr, "libassimp.so.6".ptr, "libassimp.so.5".ptr,
        ];

        AssimpSupport last = AssimpSupport.noLibrary;
        foreach (name; candidates) {
            last = loadAssimp(name);
            if (last == AssimpSupport.loaded) return last;
        }
        return last;
    }

    /// Loads the assimp shared library from an explicit path / SONAME and binds
    /// every symbol declared in bindbc.assimp.bind.core. Missing symbols are
    /// accumulated via bindbc-loader's error log — inspect with `errors()`.
    AssimpSupport loadAssimp(const(char)* libName) nothrow @nogc {
        lib = bindbc.loader.load(libName);
        if (lib == invalidHandle) return AssimpSupport.noLibrary;

        const errBefore = errorCount();
        bindbc.assimp.bind.core.bindModuleSymbols(lib);
        if (errorCount() != errBefore) return AssimpSupport.badLibrary;
        return AssimpSupport.loaded;
    }
}

// --- inline helpers ---------------------------------------------------------
//
// assimp declares these two as AI_FORCE_INLINE in material.inl, so they are
// not exported symbols. Reproduce them here as thin wrappers, matching the
// upstream behaviour (pMax == null).

/// Retrieve a single float property from a material (see aiGetMaterialFloatArray).
aiReturn aiGetMaterialFloat(const(aiMaterial)* pMat, const(char)* pKey,
                            uint type, uint index, ai_real* pOut) nothrow @nogc {
    return aiGetMaterialFloatArray(pMat, pKey, type, index, pOut, null);
}

/// Retrieve a single integer property from a material (see aiGetMaterialIntegerArray).
aiReturn aiGetMaterialInteger(const(aiMaterial)* pMat, const(char)* pKey,
                              uint type, uint index, int* pOut) nothrow @nogc {
    return aiGetMaterialIntegerArray(pMat, pKey, type, index, pOut, null);
}
