# Inertia Animation Library

## Overview
An editor application and library for creating in-app, native, keyframe animations with a WYSIWYG (what you see is what you get) editor.

## Demo Video


https://github.com/user-attachments/assets/b3251bed-75bd-4967-a8c7-8927c85d3f48


## Intro

Welcome to Inertia, a cross-platform animation library for SwiftUI.

Inertia bridges designers and developers with a keyframe editor that exports animation files, which integrate directly into your native UI code.

Unlike other libraries, Inertia lets you animate real UI components on each platform while leveraging native animation engines:
- SwiftUI → built on iOS 17+ keyframe animations

## Features

🎨 Keyframe editor with JSON export  
🔐 Strongly typed IDs for safe animation references  
🎛️ Control lifecycle: trigger, cancel, restart  
⚡ Minimal boilerplate  
🎯 Editor mode for live design and testing  

## Installation

### SwiftUI (iOS)

```swift
import Inertia
```


## Usage

### 1. Define Animation IDs (SwiftUI)

Animation IDs can be simple strings:

```swift
// Simple string approach
let cardAnimationId = "card0"
let carAnimationId = "car"

// Or use enum for better organization (optional)
enum AnimationID: String, CaseIterable {
    case card0, car, planeTop, planeBottom, homeCard
}
```

### 2. Set Up the Animation Container

Wrap your app's root view in an InertiaContainer. The container loads animations and provides the animation context to child views.

```swift
import SwiftUI
import Inertia

struct AppEnvironment {
    #if INERTIA_EDITOR
    static let isInertiaEditor = true
    #else
    static let isInertiaEditor = false
    #endif
}

@main
struct InertiaDemoApp: App {
    var body: some Scene {
        WindowGroup {
            InertiaContainer(
                dev: AppEnvironment.isInertiaEditor, // enables editor mode when compiled with INERTIA_EDITOR
                id: "animation",                     // animation bundle id (matches JSON filename)
                hierarchyId: "animation2"            // unique hierarchy identifier
            ) {
                ContentView()
            }
        }
    }
}
```

### 3. Apply Animations to Views

Use the `.inertia()` modifier to make any view animatable:

```swift
struct ContentView: View {
    var body: some View {
        VStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.blue)
                .frame(width: 200, height: 120)
                .overlay {
                    Text("Card")
                        .foregroundStyle(.white)
                }
                .inertia("card0")  // Apply animation with string ID

            Button("Animate") {
                // Animation triggers are handled through the JSON configuration
            }
            .inertia("animateButton")
        }
        .padding()
    }
}
```

### 4. Animation Control (Optional)

For programmatic control, access the InertiaViewModel through the environment:

```swift
struct ContentView: View {
    @EnvironmentObject private var inertia: InertiaViewModel

    var body: some View {
        VStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.blue)
                .frame(width: 200, height: 120)
                .inertia("card0")

            Button("Trigger Animation") {
                trigger("card0")
            }
        }
    }

    private func trigger(_ id: String) {
        inertia.trigger(id)
    }

    private func toggle(_ id: String) {
        if inertia.isCancelled(id) {
            inertia.restart(id)
        } else {
            inertia.cancel(id)
        }
    }
}
```

## Animation File Structure

Animations are defined as JSON arrays containing animation objects. Each animation object specifies the element ID to animate along with its keyframes.

Example `animation.json`:

```json
[
  {
    "id": "card0",
    "initialValues": {
      "opacity": 1,
      "rotate": 0,
      "rotateCenter": 0,
      "scale": 1,
      "translate": [0, 0]
    },
    "invokeType": "auto",
    "keyframes": [
      {
        "duration": 1,
        "id": "ADC3E556-DFF1-4B66-BB1F-4C77CA0E3727",
        "values": {
          "opacity": 1,
          "rotate": 0,
          "rotateCenter": 0,
          "scale": 1,
          "translate": [-0.016666666666666666, 0.06620209059233449]
        }
      },
      {
        "duration": 1,
        "id": "3117F4DE-3BEC-44F4-93CC-1ADC735083DE",
        "values": {
          "opacity": 1,
          "rotate": 0,
          "rotateCenter": 0,
          "scale": 1,
          "translate": [-0.02, 0.627177700348432]
        }
      }
    ]
  }
]
```

## Animation Properties

- `id`: Unique identifier matching the view's `.inertia()` modifier
- `initialValues`: Starting state for all animation properties
- `invokeType`: Animation trigger mode (`"auto"` or `"trigger"`)
- `keyframes`: Array of animation steps with values and durations

### Animatable Values

- `scale`: Scale factor (1.0 = normal size)
- `translate`: [x, y] position offset as percentage of container size
- `rotate`: Rotation from top-left anchor (degrees)
- `rotateCenter`: Rotation from center anchor (degrees)
- `opacity`: Transparency (0.0 = invisible, 1.0 = opaque)
- `duration`: Keyframe duration in seconds

## Invoke Types

- `"auto"`: Animation starts automatically when view appears
- `"trigger"`: Animation waits for programmatic trigger

## Editor Mode

Enable editor mode during development by:

1. Adding INERTIA_EDITOR build flag
2. Setting `dev: true` in InertiaContainer
3. Running your app - you'll see:
   - Selection borders around animatable views
   - Live editing capabilities
   - Real-time animation preview

The editor connects via WebSocket to design tools for live collaboration.

## Complete Example

```swift
import SwiftUI
import Inertia

struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            // Animated card that moves automatically
            RoundedRectangle(cornerRadius: 12)
                .fill(.blue)
                .frame(width: 200, height: 120)
                .overlay {
                    Text("Card")
                        .foregroundStyle(.white)
                }
                .inertia("card0")

            // Another animated card with manual trigger
            RoundedRectangle(cornerRadius: 12)
                .fill(.purple)
                .frame(width: 200, height: 120)
                .overlay {
                    Text("Home Card")
                        .foregroundStyle(.white)
                }
                .inertia("homeCard")
                .onTapGesture {
                    // Trigger handled by animation configuration
                }

            // Multiple planes with individual animations
            HStack {
                Image(systemName: "airplane")
                    .inertia("planeTop")

                Image(systemName: "airplane")
                    .inertia("planeBottom")
            }
            .font(.largeTitle)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@main
struct InertiaDemoApp: App {
    var body: some Scene {
        WindowGroup {
            InertiaContainer(
                dev: false,  // Set to true for editor mode
                id: "animation",
                hierarchyId: "mainContainer"
            ) {
                ContentView()
            }
        }
    }
}
```

## Key Differences from Other Animation Libraries

- **Design-First**: Animations are defined in JSON, enabling designer-developer collaboration
- **Native Performance**: Uses each platform's native animation engines
- **Live Editing**: Editor mode enables real-time animation tweaking
- **Minimal Code**: Apply animations with a single modifier

## Roadmap

✅ SwiftUI support  
Jetpack Compose support  
React support  

---

*Inertia Team • 2025*
