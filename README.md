#  Stream Deck Xcode Plugin

This repository contains a Stream Deck plugin to add some useful Xcode actions to your Stream Deck.

It _also_ contains a handy template for building your own Stream Deck plugins, and the project is designed to be a great starting off point for a new plugin. You'll find more details on that [below](#stream-deck-plugin-template).

<p align="center">
  <img src="https://github.com/ikenndac/xcode-streamdeck-plugin/blob/main/Documentation%20Images/Stream%20Deck%20Screenshot.png?raw=true" width="484" alt="Screenshot"/>
</p>


### Installation & Use

To use the plugin, download the latest release from the [Releases](https://github.com/iKenndac/xcode-streamdeck-plugin/releases) page and double-click it to install it into the Stream Deck application. Once installed, you'll see a new **Xcode** category containing some new actions:

- **Toggle Breakpoints** toggles breakpoints on and off.

- **Pause Debugger** pauses or resumes the current debugger session.

- **View Debugger** triggers the view debugger.

The actions target the frontmost Xcode window for getting state and triggering actions.


### How Does It Work?

The plugin uses the Accessibility APIs to interact with Xcode. If it doesn't seem to work, make sure the Stream Deck application has Accessibility access in the Security & Privacy pane of System Preferences and restart it.

If you're interested in the details, the meat of the logic is implemented in the `XcodeObserver.swift` file.


### What Problem Does This Solve?

This plugin attempts to bring back the best feature of the MacBook Pro Touch Bar (in my opinion) — global debugger actions. Being able to manipulate Xcode while the app you're debugging is frontmost is really useful in some situations:

- Let's say you have an exception breakpoint set, and you want to target some specific exceptions. If code in your app uses exceptions for flow control (which can be quite common in Swift), this can be a bit of a nightmare to get through. Being able to enable/disable breakpoints while your app is frontmost makes this much easier — just keep breakpoints disabled until you're at the correct point in your app's lifecycle, tap the button on your Stream Deck, and off you go!

- Often the most tricky UI bugs to figure out are transient ones — bugs that happen during transitions or other animations. Triggering the view debugger at the right instant is critical for this, and being able to trigger it while your app is frontmost makes it a lot easier to get exactly the right moment captured.


# Stream Deck Plugin Template

Alongside the Xcode plugin, this project contains a plugin template that makes it super easy to make your own Stream Deck plugins in Swift. It's heavily inspired by the excellent [streamdeck-template-swift](https://github.com/JarnoLeConte/streamdeck-template-swift) project by Jarno Le Conté, but differs in a couple of meaningful ways:

- It's 100% Swift.

- It uses the system-provided WebSocket APIs available from macOS 10.15, which means there are no external dependencies.

- It performs a lot more packaging and distribution work as part of the build process, making the build process completely self-contained in Xcode.


### How To Use

The plugin template implements the underlying Stream Deck protocols for you, handing plugin registration, message handling, and so on. The project also contains a number of build phases that construct the correct plugin structure on disk and packages it using Elgato's own [DistributionTool](https://developer.elgato.com/documentation/stream-deck/sdk/exporting-your-plugin/), which is included in this repo.

 Everything in the `Common Sources` folder should be used without modification. To build your own plugin:

- Edit `Build Settings.xcconfig` with your plugin's details. The values in this file are used in several places in the build process: filling out the `manifest.json` file required by the Stream Deck plugin architecture, naming files on disk, and embedding values into the plugin binary. This config file makes sure everything stays in sync.

- Edit `manifest.json` to add your plugin's actions. Don't edit the values that look like `$(PLUGIN_CATEGORY)` — they'll be filled in automatically at build time. Details on the actions structure can be found [here](https://developer.elgato.com/documentation/stream-deck/sdk/manifest/).

- Make a new class that implements the `ESDConnectionManagerDelegate` protocol. This is where your plugin's core logic lives. You'll find an empty implementation in the `BasicPluginImplementation.swift` file.

- Modify the `createEventHandler()` function in `PluginImplementation.swift` to return a new instance of your class when called.

- Build the `Stream Deck Plugin` target. All being well, you'll have a packaged plugin! Choose Product → Show Build Folder in Finder to get at it.

### Implementing a Plugin

The methods implemented in your plugin class from `ESDConnectionManagerDelegate` are your interaction point with the Stream Deck. Take a look in `ESDConnectionManagerDelegate.swift` for documentation. A few pointers:

- `connectionManagerDidEstablishConnectionToPluginHost(_:)` will be called very early in the plugin's lifecycle, giving you a connection manager you can use to perform actions on the Stream Deck. See the documentation in `ESDConnectionManager.swift` for what you can do.

- When you receive events and otherwise interact with the Stream Deck Plugin API, you'll see references to an `actionIdentifier`,  a `deviceIdentifier`, and a `context`:

    - The `actionIdentifier` refers to the kind of action for a given item. The Xcode plugin has three actions — toggle breakpoints, pause debugger, and view debugger. In the Xcode plugin, only the `actionIdentifier` is checked when a key is pressed — we don't care which exact key on the device the command came from, just what the user wants to do.

    - The `deviceIdentifier` refers to a physical piece of hardware. If you care, the method `connectionManager(_, deviceDidConnect:, deviceInfo:)` will be called as hardware devices become available. You can get details of the hardware here.

    - The `context` refers to a specific instance of an action. Since an action can be placed into multiple screens on a Stream Deck (or even multiple times on one screen), the context disambiguates between them. In the Xcode plugin, we use the `context` when an action fails — we want to put a warning icon on the exact button the user actually pressed.

- In general, the template is a no-frills implementation of the Stream Deck SDK. Reading through and understanding the [Elgato Documentation](https://developer.elgato.com/documentation/stream-deck/sdk/overview/) will get you a long way — particularly the **Manifest**, **Events Received**, **Events Sent**, **Create your own plugin**, and **Style Guide** sections.

