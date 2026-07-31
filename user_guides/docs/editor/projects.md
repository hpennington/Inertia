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
        └── animation.json
```

| Path | Contents |
| --- | --- |
| `MyProject.inertia/` | The project. The name before `.inertia` is the project title. |
| `meta.json` | Project metadata — the target framework and the project title. |
| `animations/animation.json` | Every animation in the project. This is the file your app bundles. |

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
cp ~/InertiaStorage/MyProject.inertia/animations/animation.json \
   path/to/MyApp/animation.json
```

The file must end up in **Copy Bundle Resources** for your target, and its name must
match the `id` you passed to `InertiaContainer` — `id: "animation"` loads
`animation.json`.

!!! tip "Symlink instead of copying"

    If you get tired of copying, symlink the project's animation file into your Xcode
    project once:

    ```sh
    ln -s ~/InertiaStorage/MyProject.inertia/animations/animation.json \
          path/to/MyApp/animation.json
    ```

    Xcode copies through the symlink at build time, so a rebuild picks up whatever the
    editor last saved. The tradeoff is that your repository no longer records the
    animation as it shipped — commit the real file before you tag a release.

## Version control

`animation.json` is ordinary JSON with stable key ordering, so it diffs reasonably.
Keyframe ids are UUIDs generated when the keyframe is recorded and are stable across
saves, which keeps diffs limited to what actually changed.

The project directory is worth committing alongside your app if the animations are part
of the product.
