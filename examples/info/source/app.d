/// Loads libassimp at runtime and prints a summary of a model file.
///
///   dub run -- path/to/model.obj
///
/// With no argument it builds a tiny in-memory OBJ and imports that instead,
/// so the example is self-contained.
import core.stdc.string : strlen;
import std.stdio;
import std.string : fromStringz, toStringz;

import bindbc.assimp;

void main(string[] args)
{
    // 1. Bring in the shared library.
    const support = loadAssimp();
    if (support != AssimpSupport.loaded) {
        stderr.writeln("failed to load libassimp: ", support);
        version (BindBC_Static) {} else {
            import bindbc.loader : errors;
            foreach (e; errors)
                stderr.writeln("  ", e.error.fromStringz, ": ", e.message.fromStringz);
        }
        return;
    }
    scope(exit) unloadAssimp();

    writefln("assimp runtime: %d.%d.%d (rev %#x)",
        aiGetVersionMajor(), aiGetVersionMinor(), aiGetVersionPatch(),
        aiGetVersionRevision());

    // 2. Import a scene — either the file given on the command line, or a
    //    built-in triangle so the example runs with no arguments.
    const(aiScene)* scene;
    if (args.length > 1) {
        scene = aiImportFile(args[1].toStringz,
            aiProcess_Triangulate | aiProcess_GenNormals | aiProcess_JoinIdenticalVertices);
    } else {
        static immutable string obj =
            "o tri\n"
            ~ "v 0 0 0\nv 1 0 0\nv 0 1 0\n"
            ~ "f 1 2 3\n";
        scene = aiImportFileFromMemory(obj.ptr, cast(uint) obj.length,
            aiProcess_Triangulate, "obj".ptr);
    }

    if (scene is null) {
        stderr.writeln("import failed: ", aiGetErrorString().fromStringz);
        return;
    }
    scope(exit) aiReleaseImport(scene);

    // 3. Walk the result.
    writefln("flags=%#x  meshes=%d  materials=%d  textures=%d  lights=%d  cameras=%d  animations=%d",
        scene.mFlags, scene.mNumMeshes, scene.mNumMaterials, scene.mNumTextures,
        scene.mNumLights, scene.mNumCameras, scene.mNumAnimations);

    foreach (i; 0 .. scene.mNumMeshes) {
        const(aiMesh)* m = scene.mMeshes[i];
        writefln("  mesh[%d] \"%s\": %d verts, %d faces, %d bones, mat #%d",
            i, m.mName.data[0 .. m.mName.length], m.mNumVertices, m.mNumFaces,
            m.mNumBones, m.mMaterialIndex);
        // Walking the bone array dereferences aiBone — a good ABI check.
        foreach (b; 0 .. (m.mNumBones > 3 ? 3 : m.mNumBones)) {
            const(aiBone)* bone = m.mBones[b];
            writefln("    bone[%d] \"%s\": %d weights",
                b, bone.mName.data[0 .. bone.mName.length], bone.mNumWeights);
        }
    }

    foreach (i; 0 .. scene.mNumMaterials) {
        const(aiMaterial)* mat = scene.mMaterials[i];
        aiString name;
        if (aiGetMaterialString(mat, AI_MATKEY_NAME.key,
                AI_MATKEY_NAME.semantic, AI_MATKEY_NAME.index, &name) == aiReturn.SUCCESS)
            writefln("  material[%d] \"%s\"", i, name.data[0 .. name.length]);
    }
}
