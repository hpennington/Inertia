# Installation

Pick your runtime below. The tab you choose is remembered across this site, so the rest of
the guides will show you the same one.

## Requirements

| | SwiftUI | Compose | React |
| --- | --- | --- | --- |
| App target | iOS 17+ (or macOS 14+) | `minSdk` 26, `compileSdk` 34 | React 18.3.1 |
| Language | Swift 5.9+ / SwiftUI | Kotlin 2.0+, JVM 17 | TypeScript 5.5+ |
| Editor | macOS, with `xcrun simctl` | macOS, with `adb` on `PATH` | macOS |

The editor is a macOS app in every case. What differs is what it drives: an iOS Simulator,
an Android emulator, or your web dev server in a web view.

=== "SwiftUI"

    ## Add the Swift package

    In Xcode, choose **File → Add Package Dependencies…** and enter:

    ```
    https://github.com/hpennington/Inertia
    ```

    Add the `Inertia` library product to your app target.

    Or declare it in a `Package.swift`:

    ```swift
    dependencies: [
        .package(url: "https://github.com/hpennington/Inertia", branch: "main")
    ],
    targets: [
        .target(
            name: "MyApp",
            dependencies: ["Inertia"]
        )
    ]
    ```

    Then import it wherever you use it:

    ```swift
    import Inertia
    ```

    The iOS 17 floor is not arbitrary: the runtime plays your tracks through SwiftUI's
    `KeyframeAnimator`, which is an iOS 17 API.

    ## Add the animation file to your target

    The runtime loads animations from a [MessagePack](https://msgpack.org) resource in
    your app bundle, looked up by the container's `id`. A container created with
    `id: "animation"` reads `animation.inertia`.

    1. Create an empty `animation.inertia` next to your Swift sources. The file is
       binary, so it cannot be typed into an editor — an empty array is the single
       byte `0x90`:

        ```sh
        printf '\x90' > animation.inertia
        ```

    2. Drag it into your Xcode project.
    3. Confirm it appears under **Target → Build Phases → Copy Bundle Resources**.

    !!! warning "The file is required in release builds"

        Outside editor mode, `InertiaContainer` reads this resource during
        initialization and traps if it is missing or fails to decode. An empty
        array is a valid animation file; a missing file is not.

    Once the editor is writing animations for this project, you copy its `animation.inertia`
    over this one. See [Projects](../editor/projects.md) for where the editor keeps it.

    ## Add the editor build flag

    Editor mode should be compiled in for development builds only. The convention used by
    the example app is a `INERTIA_EDITOR` Swift flag on a dedicated scheme or build
    configuration:

    1. Select your target → **Build Settings**.
    2. Find **Other Swift Flags** (`OTHER_SWIFT_FLAGS`).
    3. For the configuration you want to edit in, add `-D INERTIA_EDITOR`.

    Then read it in one place:

    ```swift
    struct AppEnvironment {
        #if INERTIA_EDITOR
        static let isInertiaEditor = true
        #else
        static let isInertiaEditor = false
        #endif
    }
    ```

=== "Compose"

    ## Add the Gradle dependency

    The runtime is published through JitPack. Add the repository in
    `settings.gradle.kts`:

    ```kotlin title="settings.gradle.kts"
    dependencyResolutionManagement {
        repositories {
            google()
            mavenCentral()
            maven { url = uri("https://jitpack.io") }
        }
    }
    ```

    Then the artifact in your app module:

    ```kotlin title="app/build.gradle.kts"
    dependencies {
        implementation("com.github.hpennington:inertia-compose:v1.0.8")
    }
    ```

    Everything is in one package:

    ```kotlin
    import org.inertiagraphics.inertia.InertiaContainer
    import org.inertiagraphics.inertia.Inertia
    import org.inertiagraphics.inertia.LocalInertia
    ```

    !!! tip "Building against a checkout instead"

        To work against the runtime source rather than a published release — which is
        what the demo app in the repository does — include it as a composite build and
        substitute the module:

        ```kotlin title="settings.gradle.kts"
        includeBuild("../path/to/runtime-compose/inertia-compose") {
            dependencySubstitution {
                substitute(module("com.github.hpennington:inertia-compose"))
                    .using(project(":lib"))
            }
        }
        ```

    ## Allow cleartext WebSocket traffic

    The runtime dials the editor over plain `ws://`, and cleartext has been denied by
    default since `targetSdk` 28. Grant the permission and permit the hosts you may dial
    the editor at:

    ```xml title="src/main/AndroidManifest.xml"
    <uses-permission android:name="android.permission.INTERNET" />

    <application android:networkSecurityConfig="@xml/network_security_config" …>
    ```

    ```xml title="src/main/res/xml/network_security_config.xml"
    <?xml version="1.0" encoding="utf-8"?>
    <network-security-config>
        <domain-config cleartextTrafficPermitted="true">
            <!-- Reaches the editor through the `adb reverse` tunnel it opens. -->
            <domain includeSubdomains="true">127.0.0.1</domain>
            <domain includeSubdomains="true">localhost</domain>
            <!-- The stock emulator's route to the host machine. -->
            <domain includeSubdomains="true">10.0.2.2</domain>
        </domain-config>
    </network-security-config>
    ```

    Keep this to the hosts you actually need, and prefer a `debug` source set over the
    main manifest if the app is ever going to be released.

    ## Add the animation file

    Put the `animation.inertia` the editor exported in your app's assets:

    ```
    app/src/main/assets/animation.inertia
    ```

    The basename has to match the container's `id`. With `dev = false` the container reads
    it from there; with `dev = true` it ignores the file and takes its schemas from the
    editor over the socket instead.

    Wire `dev` to a build flag so a release build never dials the editor:

    ```kotlin
    InertiaContainer(
        dev = BuildConfig.DEBUG,
        id = "animation",
        hierarchyId = "animation",
        baseURL = "ws://127.0.0.1:8070"
    ) { App() }
    ```

=== "React"

    ## Install the package

    The React runtime is two npm packages, both published to the registry:

    - **`inertia-base`** — the framework-agnostic core: schema and message types, the
      hierarchy tree, the interpolation, the WebSocket client.
    - **`inertia-react`** — the React bindings that sit on top of it.

    `inertia-react` depends on `inertia-base`, so installing the one is enough:

    ```sh
    npm install inertia-react
    ```

    React and React DOM 18.3.1 are **peer** dependencies of `inertia-react`, so your app
    supplies them:

    ```sh
    npm install react@18.3.1 react-dom@18.3.1
    ```

    Having a second copy of React resolve inside the package breaks hooks, so keep a
    single React in your app's tree.

    Then import from it:

    ```tsx
    import { InertiaContainer, Inertia, useInertia } from "inertia-react";
    ```

    ## Serve the animation file

    Outside editor mode the container does not read a bundled file — it fetches
    `<baseURL>/<id>.inertia` over HTTP. Something has to serve the editor's animations
    directory, with CORS headers, at whatever `baseURL` you pass:

    ```sh
    cd MyProject.inertia/animations
    python3 -m http.server 8000
    ```

    The repository ships a small server that does this with
    `Access-Control-Allow-Origin: *` already set, at
    `example/demo.inertia/animations/serve_animations.py`. A plain `http.server` works too
    as long as your page is served from the same origin.

    ## Add the editor flag

    Editor mode is a prop, so drive it from the environment rather than hardcoding it:

    ```tsx
    const isDev = process.env.REACT_APP_INERTIA_DEV !== "false";
    const baseURL = process.env.REACT_APP_INERTIA_BASE_URL ?? "http://localhost:8000";
    ```

    With `dev` false the container never opens a socket, so a production bundle does not
    reach for an editor.

## Next

- [Quickstart](quickstart.md) — get a view animating.
- [Editor mode](editor-mode.md) — connect a running app to the editor.
