# Projects

An Inertia project is a directory on disk. It holds the framework the project targets
and the animations you have authored, and it is what the editor opens, saves, and
autosaves.

## Where projects live

Projects live under `InertiaStorage` in your home directory:

```
~/InertiaStorage/
└── MyProject.inertia/
    ├── meta.json
    └── animations/
        └── animation.msgpack
```

| Path | Contents |
| --- | --- |
| `MyProject.inertia/` | The project. The name before `.inertia` is the project title. |
| `meta.json` | Project metadata — the target framework and the project title. |
| `animations/animation.msgpack` | Every animation in the project. This is the file your app bundles. |

`meta.json` is small:

```json title="meta.json"
{
    "framework": "swiftUI",
    "projectTitle": "MyProject"
}
```

Both keys are required — the editor fails to open a project whose `meta.json` is missing
either one.

## Creating a project

From the start screen, choose **New project**, give it a title, and the editor creates
the directory structure for you. Choosing **Open project** instead lets you pick an
existing `.inertia` directory.

Opening a project loads its animations into the timeline, with each track's playhead
parked at the end of what was recorded, so recording continues after the existing
keyframes rather than on top of them.

## Getting animations into your app

The editor writes only to its own project directory. Shipping an animation means copying
the file into your Xcode project:

```sh
cp ~/InertiaStorage/MyProject.inertia/animations/animation.msgpack \
   path/to/MyApp/animation.msgpack
```

The file must end up in **Copy Bundle Resources** for your target, and its name must
match the `id` you passed to `InertiaContainer` — `id: "animation"` loads
`animation.msgpack`.

!!! tip "Symlink instead of copying"

    If you get tired of copying, symlink the project's animation file into your Xcode
    project once:

    ```sh
    ln -s ~/InertiaStorage/MyProject.inertia/animations/animation.msgpack \
          path/to/MyApp/animation.msgpack
    ```

    Xcode copies through the symlink at build time, so a rebuild picks up whatever the
    editor last saved. The tradeoff is that your repository no longer records the
    animation as it shipped — commit the real file before you tag a release.

## Version control

`animation.msgpack` is binary, so git will treat it as such and no diff will be
readable. What keeps it from churning is that the editor writes the store sorted by
id, and keyframe ids are UUIDs generated when the keyframe is recorded and stable
across saves — so an unchanged animation re-saves to identical bytes.

To read a change, decode it. Any MessagePack CLI will do; with Python:

```sh
python3 -c "import msgpack,sys,json; print(json.dumps(msgpack.unpack(open(sys.argv[1],'rb')), indent=2))" \
    animations/animation.msgpack
```

The project directory is worth committing alongside your app if the animations are part
of the product.
