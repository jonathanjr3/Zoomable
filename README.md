# Zoomable

A SwiftUI wrapper over UIScrollView that allows displaying any content and zooming in and out of it through pinch gesture. Double tap toggles between fit and zoomed in. Once zoomed in, the content can be scrolled.

Getting a zoomable image becomes as simple as
```swift
import SwiftUI
import Zoomable

struct ContentView: View {
    var body: some View {
        Zoomable {
            Image("bird_wildlife_sky_clouds")
        }
    }
}
```

## Options
```swift
Zoomable { Image(uiImage: image) }
    .secondaryZoomLevel(.scaledFit(scale: 2.5)) // double tap target, zooms towards the tapped point
    .maximumZoomScale(10)
    .scrollIndicators(false)
    .zoomDisabled(isTransitioning)               // temporarily turn off all interaction
    .isZoomed($isZoomed)                         // observe whether the content is zoomed in
```
Double tap toggles between the primary and secondary zoom levels. Rotating the device resets the zoom.
