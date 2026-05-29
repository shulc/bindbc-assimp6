# D-Assimp (bindbc-assimp6)

D bindings for the [Open Asset Import Library (assimp)](https://github.com/assimp/assimp) **6.0.5**.
Bindbc-style: dynamic loading via `bindbc-loader` by default, optional static
binding behind `version=BindAssimp_Static`.

Covers the full assimp **C API** — 129 functions across `cimport.h`,
`cexport.h`, `version.h`, `material.h` and `importerdesc.h` — plus hand-audited
translations of every public C struct/enum (`aiScene`, `aiMesh`, `aiMaterial`,
`aiAnimation`, `aiSkeleton`, the math types, the post-processing flags, the
material-key macros, …).

Confirmed working against the system `libassimp.so.6`: dynamic load, import OBJ /
FBX / MD5 / glTF models, walk meshes, bones, and materials. See `examples/info/`.

## Status

The binding targets the **6.0.5** headers. assimp keeps a stable ABI across the
6.0.x patch line, so it also loads against 6.0.x runtimes (tested against the
distro `libassimp.so.6`, reported version 6.0.4). The C++ `Importer`/`Exporter`
classes are intentionally not bound — use the C entry points (`aiImportFile*`,
`aiExportScene*`).

## Dependencies

- DUB + DMD/LDC
- `bindbc-common ~>1.0.5`, `bindbc-loader ~>1.1.5` (pulled by DUB)
- An assimp 6.0.x runtime: `libassimp.so.6` / `assimp.dll` / `libassimp.6.dylib`
  on the loader search path (install via your package manager, or build the
  `extern/assimp` submodule).

## Use

```d
import bindbc.assimp;

if (loadAssimp() != AssimpSupport.loaded) {
    // inspect bindbc.loader.errors()
    return;
}
scope(exit) unloadAssimp();

const(aiScene)* scene = aiImportFile("model.obj",
    aiProcess_Triangulate | aiProcess_GenNormals | aiProcess_JoinIdenticalVertices);
if (scene is null) {
    import std.string : fromStringz;
    stderr.writeln(aiGetErrorString().fromStringz);
    return;
}
scope(exit) aiReleaseImport(scene);

foreach (i; 0 .. scene.mNumMeshes) {
    const(aiMesh)* m = scene.mMeshes[i];
    writefln("%s: %d verts", m.mName.data[0 .. m.mName.length], m.mNumVertices);
}
```

### Material keys

Material properties are addressed by a `(name, semantic, index)` triple,
exposed as `AiMatKey` values:

```d
aiString name;
aiGetMaterialString(mat, AI_MATKEY_NAME.key, AI_MATKEY_NAME.semantic,
                    AI_MATKEY_NAME.index, &name);

ai_real metallic;
aiGetMaterialFloat(mat, AI_MATKEY_METALLIC_FACTOR.key,
                   AI_MATKEY_METALLIC_FACTOR.semantic,
                   AI_MATKEY_METALLIC_FACTOR.index, &metallic);
```

Texture-bound keys are templates parameterised by texture type and slot:

```d
enum k = AI_MATKEY_TEXTURE!(aiTextureType.DIFFUSE, 0);
aiString path;
aiGetMaterialString(mat, k.key, k.semantic, k.index, &path);
```

## Configurations

| DUB config | Binding |
|------------|---------|
| `dynamic` (default) | runtime `dlopen`/`LoadLibrary` via bindbc-loader |
| `static`            | link-time against the assimp import library (`version=BindAssimp_Static`) |

```d
// dub.json of a consumer project
"subConfigurations": { "bindbc-assimp6": "dynamic" }
```

> Note: `-betterC` is not supported — the dynamic loader codegen from
> `bindbc-common` relies on associative arrays at compile time.

## Layout

```
source/bindbc/assimp/
├── package.d        # loadAssimp / unloadAssimp, AssimpSupport, inline helpers
├── config.d         # staticBinding flag (version=BindAssimp_Static)
├── codegen.d        # bindbc-common joinFnBinds alias
└── bind/
    ├── types.d      # HAND-MAINTAINED — structs, enums, #define constants
    └── core.d       # AUTO — FnBind[] for the whole C API

tools/gen_binds.py   # regenerate bind/core.d from the C-API headers
examples/info/       # runtime load + import + summary
extern/assimp/       # upstream assimp, pinned to v6.0.5 (git submodule)
```

`bind/types.d` is hand-written and audited field-by-field against the headers:
assimp's data types are heavily-templated C++ (`aiVector3t!TReal`, …) that no
regex can translate safely. Only the flat `extern "C"` function surface in
`bind/core.d` is generated.

### Regenerating the function bindings

```bash
git submodule update --init extern/assimp
python3 tools/gen_binds.py extern/assimp/include/assimp
dub build
```

## License

- Bindings: Boost Software License 1.0 (matches the bindbc family).
- assimp itself is distributed under its own modified BSD 3-clause license.
