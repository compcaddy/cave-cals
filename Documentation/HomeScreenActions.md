# Home Screen logging

Long-press **Cave Cals** to choose **Voice Log**, **Image Scan**, **Barcode Scan**, or **Add Food**.

Add the **Quick Log** widget from the Home Screen widget gallery under **Cave Cals**. It uses the medium size and has four separate buttons: barcode, voice, image, and plus. Plus opens the existing food search/add drawer. Image opens photo logging, including camera and photo-library choices; voice opens voice logging. Recording and uploading still require the user's normal in-app actions.

All external actions start on today's date. If initial setup is required, the action waits until setup is complete. A shortcut takes precedence over the search drawer that normally opens when the app starts or resumes.

## Implementation

- `Shared/LoggingAction.swift` is compiled into the app and widget and defines the four URLs: `cavecals://log/{barcode,voice,image,add}`.
- `App/Info.plist` registers the URL scheme and four static Home Screen shortcuts, available before the app's first launch.
- `QuickActionAppDelegate` captures cold-launch shortcut connection options. `QuickActionSceneDelegate` handles running-app shortcuts. Both feed the same observable router as SwiftUI's `onOpenURL`.
- `MainView` consumes requests only when it is available, after setup, and selects the existing logging drawer.
- `QuickLogWidget` is embedded as an app extension. It contains only navigation links, so it needs no shared database, App Group, network access, or background refresh.
- The Xcode project generator includes the shared source, extension target, dependency, and embedding phase. Keep the extension's marketing/build versions aligned with the containing app when releasing.

The widget supports iOS 17 and later. Its medium size follows [Apple's guidance for multiple widget links](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension). Shortcut lifecycle handling follows [Apple's Home Screen quick action guidance](https://developer.apple.com/documentation/uikit/add-home-screen-quick-actions).

## Verification

Verified September 5, 2026:

- Debug simulator build and unsigned Release iPhone build succeeded, including the embedded widget and matching bundle versions.
- All 4 routing unit tests and all 5 navigation UI tests passed on iOS 17.2.
- On iOS 26, the medium widget rendered on the Home Screen and each of its four buttons opened the correct feature. Voice logging also continued correctly after first-time setup.
- Property lists, project-generator Ruby syntax, and whitespace checks passed.

`LoggingActionTests` checks URL validation, the installed shortcut definitions, pending requests, and repeated actions. `LoggingActionUITests` checks all four links, drawer replacement, setup deferral, cold URL launches, and warm/cold Home Screen shortcuts. Tests use an in-memory store except a launch performed directly by SpringBoard, which follows the normal launch path and may use an existing simulator profile.

Before shipping, use a signed iPhone build to check camera and microphone capture, and add the widget through the widget gallery. The simulator verifies navigation and layout but cannot validate physical camera capture.
