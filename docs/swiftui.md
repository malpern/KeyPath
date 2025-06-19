# https://developer.apple.com/documentation/swiftui/ llms-full.txt

## SwiftUI TabView Guide
[Skip Navigation](https://developer.apple.com/documentation/swiftui/tabview#app-main)

## SwiftUI Glass Effect
[Skip Navigation](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:isenabled:)#app-main)

## TabView Bottom Accessory
[Skip Navigation](https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(content:)#app-main)

## SwiftUI ImageRenderer Guide
[Skip Navigation](https://developer.apple.com/documentation/swiftui/imagerenderer#app-main)

## Fitting Images in SwiftUI
[Skip Navigation](https://developer.apple.com/documentation/swiftui/fitting-images-into-available-space#app-main)

- [SwiftUI](https://developer.apple.com/documentation/swiftui)
- [Images](https://developer.apple.com/documentation/swiftui/images)
- Fitting images into available space

Article

# Fitting images into available space

Adjust the size and shape of images in your app’s user interface by applying view modifiers.

## [Overview](https://developer.apple.com/documentation/swiftui/fitting-images-into-available-space\#Overview)

Image sizes vary widely, from single-pixel PNG files to digital photography images with millions of pixels. Because device sizes also vary, apps commonly need to make runtime adjustments to image sizes so they fit within the visible user interface. SwiftUI provides modifiers to scale, clip, and transform images to fit your interface perfectly.

### [Scale a large image to fit its container using resizing](https://developer.apple.com/documentation/swiftui/fitting-images-into-available-space\#Scale-a-large-image-to-fit-its-container-using-resizing)

Consider the image `Landscape_4.jpg`, a photograph with the dimensions 4032 x 3024, showing a water wheel, the surrounding building, and the sky above.

![A photo looking up at a water wheel and its surrounding building, with the sky and clouds above.](https://docs-assets.developer.apple.com/published/9171798f66624fb18c9f216d85d85ad3/SwiftUI-FIIAS-Landscape_4-original.jpg)

The following example loads the image directly into an [`Image`](https://developer.apple.com/documentation/swiftui/image) view, and then places it in a 300 x 400 point frame, with a blue border:

```

```

As seen in the following screenshot, the image data loads at full size into the view, so only the clouds from the upper left of the original image are visible. Because the image renders at full size, and the blue frame is smaller than the original image, the image displays beyond the area bounded by the frame.

![An image that shows a frame with a blue border overlaid on an image of a water wheel. The image is so much larger than the available space that only a portion of the sky and clouds from the upper left of the original image is visible. The image goes beyond the borders of the outline.](https://docs-assets.developer.apple.com/published/3f9b1cd8d9d65f9ffba1dcba86eca2a7/SwiftUI-FIIAS-unscaled%402x.png)

To fix this, you need to apply two modifiers to the `Image`:

- [`resizable(capInsets:resizingMode:)`](https://developer.apple.com/documentation/swiftui/image/resizable(capinsets:resizingmode:)) tells the image view to adjust the image representation to match the size of the view. By default, this modifier scales the image by reducing the size of larger images and enlarges images smaller than the view. By itself, this modifier scales each axis of the image independently.

- [`aspectRatio(_:contentMode:)`](https://developer.apple.com/documentation/swiftui/view/aspectratio(_:contentmode:)) corrects the behavior where the image scaling is different for each axis. This preserves the image’s original aspect ratio, using one of two strategies defined by the [`ContentMode`](https://developer.apple.com/documentation/swiftui/contentmode) enumeration. [`ContentMode.fit`](https://developer.apple.com/documentation/swiftui/contentmode/fit) scales the image to fit the view size along one axis, possibly leaving empty space along the other axis. [`ContentMode.fill`](https://developer.apple.com/documentation/swiftui/contentmode/fill) scales the image to fill the entire view.





```

```


![An image that shows a frame with a blue border overlaid on an image of a water wheel. The water wheel image is scaled to fit the width of the containing rectangle. Empty space extends from the bottom of the image to the bottom of the rectangle.](https://docs-assets.developer.apple.com/published/366e823084f58a2b5a02ca34a6139afa/SwiftUI-FIIAS-resizeToFit%402x.png)

### [Keep image data inside the view’s bounds using clipping](https://developer.apple.com/documentation/swiftui/fitting-images-into-available-space\#Keep-image-data-inside-the-views-bounds-using-clipping)

If you use [`ContentMode.fill`](https://developer.apple.com/documentation/swiftui/contentmode/fill) when scaling an image, a portion of an image may extend beyond the view’s bounds, unless the view matches the image’s aspect ratio exactly. The following example illustrates this problem:

```

```

![An image that shows a frame with a blue border overlaid on an image of a water wheel. The water wheel image fills its entire space vertically, and extends past the right edge of the frame horizontally.](https://docs-assets.developer.apple.com/published/ddb655ddd8af262670b93b990ec5226d/SwiftUI-FIIAS-resizeToFill-noClip%402x.png)

To prevent this problem, add the [`clipped(antialiased:)`](https://developer.apple.com/documentation/swiftui/view/clipped(antialiased:)) modifier. This modifier simply cuts off excess image rendering at the bounding frame of the view. Optionally, you can add an antialiasing behavior to apply smoothing to the edges of the clipping rectangle; this parameter defaults to `false`. The following example shows the effect of adding clipping to the previous fill-mode example:

```

```

![An image that shows a frame with a blue border overlaid on an image of a water wheel. The water wheel image fills the entire frame vertically and horizontally. The right side of the image is cut off at the right side of the rectangle.](https://docs-assets.developer.apple.com/published/677c185016ebecdd1c2a9aec138aa828/SwiftUI-FIIAS-resizeToFill-clipped%402x.png)

### [Use interpolation flags to adjust rendered image quality](https://developer.apple.com/documentation/swiftui/fitting-images-into-available-space\#Use-interpolation-flags-to-adjust-rendered-image-quality)

Rendering an image at anything other than its original size requires _interpolation_: using the existing image data to approximate a representation at a different size. Different approaches to performing interpolation have different trade-offs between computational complexity and visual quality of the rendered image. You can use the [`interpolation(_:)`](https://developer.apple.com/documentation/swiftui/image/interpolation(_:)) modifier to provide a hint for SwiftUI rendering behavior.

It’s easier to see the effect of interpolation when scaling a smaller image into a larger space, because the rendered image requires more image data than is available. Consider the following example, which renders a 34 x 34 image named `dot_green` into the same 300 x 400 container frame as before:

```

```

Passing the [`Image.Interpolation.none`](https://developer.apple.com/documentation/swiftui/image/interpolation/none) value to [`interpolation(_:)`](https://developer.apple.com/documentation/swiftui/image/interpolation(_:)) produces a highly pixelated image when rendered.

![A green dot with a darker green border, scaled to many times its original size and highly pixelated.](https://docs-assets.developer.apple.com/published/daad34a379a26fb3aa4a2727cd3530b9/SwiftUI-FIIAS-smallImage-interpolation-none%402x.png)

If you change the interpolation value to [`Image.Interpolation.medium`](https://developer.apple.com/documentation/swiftui/image/interpolation/medium), SwiftUI smoothes out the pixel data to produce an image that isn’t as pixelated:

![A green dot with a darker green border, scaled to many times its original size, but with its edges smoothed.](https://docs-assets.developer.apple.com/published/0b5ba6711c01bc4324ee89397fb1798b/SwiftUI-FIIAS-smallImage-interpolation-medium%402x.png)

### [Fill a space with a repeating image using tiling](https://developer.apple.com/documentation/swiftui/fitting-images-into-available-space\#Fill-a-space-with-a-repeating-image-using-tiling)

When you have an image that’s much smaller than the space you want to render it into, another option to fill the space is _tiling_: repeating the same image over and over again. To tile an image, pass the [`Image.ResizingMode.tile`](https://developer.apple.com/documentation/swiftui/image/resizingmode/tile) parameter to the [`resizable(capInsets:resizingMode:)`](https://developer.apple.com/documentation/swiftui/image/resizable(capinsets:resizingmode:)) modifier:

```

```

![A rectangular blue outline, 300 by 400. The repeated green dot image fills its entire space horizontally and vertically.](https://docs-assets.developer.apple.com/published/eddc5cef6d4b0fd479272e0d25df8d7c/SwiftUI-FIIAS-smallImage-tile%402x.png)

Tiling can be particuarly useful when using an image that, when placed end-to-end with copies of itself, creates a larger pattern with no visual discontinuities.

## [See Also](https://developer.apple.com/documentation/swiftui/fitting-images-into-available-space\#see-also)

### [Configuring an image](https://developer.apple.com/documentation/swiftui/fitting-images-into-available-space\#Configuring-an-image)

[`func imageScale(Image.Scale) -> some View`](https://developer.apple.com/documentation/swiftui/view/imagescale(_:))

Scales images within the view according to one of the relative sizes available including small, medium, and large images sizes.

[`var imageScale: Image.Scale`](https://developer.apple.com/documentation/swiftui/environmentvalues/imagescale)

The image scale for this environment.

[`enum Scale`](https://developer.apple.com/documentation/swiftui/image/scale)

A scale to apply to vector images relative to text.

[`enum Orientation`](https://developer.apple.com/documentation/swiftui/image/orientation)

The orientation of an image.

[`enum ResizingMode`](https://developer.apple.com/documentation/swiftui/image/resizingmode)

The modes that SwiftUI uses to resize an image to fit within its containing view.

Current page is Fitting images into available space

## SwiftUI Glass Effect
[Skip Navigation](https://developer.apple.com/documentation/swiftui/glasseffectcontainer#app-main)

## SwiftUI Navigation Transition
[Skip Navigation](https://developer.apple.com/documentation/swiftui/navigationtransition#app-main)

- [SwiftUI](https://developer.apple.com/documentation/swiftui)
- NavigationTransition

Protocol

# NavigationTransition

A type that defines the transition to use when navigating to a view.

iOS 18.0+iPadOS 18.0+Mac Catalyst 18.0+macOS 15.0+tvOS 18.0+visionOS 2.0+watchOS 11.0+

```
protocol NavigationTransition
```

## [Topics](https://developer.apple.com/documentation/swiftui/navigationtransition\#topics)

### [Getting built-in transitions](https://developer.apple.com/documentation/swiftui/navigationtransition\#Getting-built-in-transitions)

[`static var automatic: AutomaticNavigationTransition`](https://developer.apple.com/documentation/swiftui/navigationtransition/automatic)

A style that automatically chooses the appropriate presentation transition for the current context.

[`static func zoom(sourceID: some Hashable, in: Namespace.ID) -> ZoomNavigationTransition`](https://developer.apple.com/documentation/swiftui/navigationtransition/zoom(sourceid:in:))

A navigation transition that zooms the appearing view from a given source view.

### [Supporting Types](https://developer.apple.com/documentation/swiftui/navigationtransition\#Supporting-Types)

[`struct AutomaticNavigationTransition`](https://developer.apple.com/documentation/swiftui/automaticnavigationtransition)

A style that automatically chooses the appropriate presentation transition for the current context.

[`struct ZoomNavigationTransition`](https://developer.apple.com/documentation/swiftui/zoomnavigationtransition)

A navigation transition that zooms the appearing view from a given source view. Indicate the source view using the `View/matchedTransitionSource(id:namespace:)` modifier.

## [Relationships](https://developer.apple.com/documentation/swiftui/navigationtransition\#relationships)

### [Conforming Types](https://developer.apple.com/documentation/swiftui/navigationtransition\#conforming-types)

- [`AutomaticNavigationTransition`](https://developer.apple.com/documentation/swiftui/automaticnavigationtransition)
- [`ZoomNavigationTransition`](https://developer.apple.com/documentation/swiftui/zoomnavigationtransition)

## [See Also](https://developer.apple.com/documentation/swiftui/navigationtransition\#see-also)

### [Defining transitions](https://developer.apple.com/documentation/swiftui/navigationtransition\#Defining-transitions)

[`func transition(_:)`](https://developer.apple.com/documentation/swiftui/view/transition(_:))

Associates a transition with the view.

[`protocol Transition`](https://developer.apple.com/documentation/swiftui/transition)

A description of view changes to apply when a view is added to and removed from the view hierarchy.

[`struct TransitionProperties`](https://developer.apple.com/documentation/swiftui/transitionproperties)

The properties a `Transition` can have.

[`enum TransitionPhase`](https://developer.apple.com/documentation/swiftui/transitionphase)

An indication of which the current stage of a transition.

[`struct AsymmetricTransition`](https://developer.apple.com/documentation/swiftui/asymmetrictransition)

A composite `Transition` that uses a different transition for insertion versus removal.

[`struct AnyTransition`](https://developer.apple.com/documentation/swiftui/anytransition)

A type-erased transition.

[`func contentTransition(ContentTransition) -> some View`](https://developer.apple.com/documentation/swiftui/view/contenttransition(_:))

Modifies the view to use a given transition as its method of animating changes to the contents of its views.

[`var contentTransition: ContentTransition`](https://developer.apple.com/documentation/swiftui/environmentvalues/contenttransition)

The current method of animating the contents of views.

[`var contentTransitionAddsDrawingGroup: Bool`](https://developer.apple.com/documentation/swiftui/environmentvalues/contenttransitionaddsdrawinggroup)

A Boolean value that controls whether views that render content transitions use GPU-accelerated rendering.

[`struct ContentTransition`](https://developer.apple.com/documentation/swiftui/contenttransition)

A kind of transition that applies to the content within a single view, rather than to the insertion or removal of a view.

[`struct PlaceholderContentView`](https://developer.apple.com/documentation/swiftui/placeholdercontentview)

A placeholder used to construct an inline modifier, transition, or other helper type.

[`func navigationTransition(some NavigationTransition) -> some View`](https://developer.apple.com/documentation/swiftui/view/navigationtransition(_:))

Sets the navigation transition style for this view.

[`func matchedTransitionSource(id: some Hashable, in: Namespace.ID) -> some View`](https://developer.apple.com/documentation/swiftui/view/matchedtransitionsource(id:in:))

Identifies this view as the source of a navigation transition, such as a zoom transition.

[`func matchedTransitionSource(id: some Hashable, in: Namespace.ID, configuration: (EmptyMatchedTransitionSourceConfiguration) -> some MatchedTransitionSourceConfiguration) -> some View`](https://developer.apple.com/documentation/swiftui/view/matchedtransitionsource(id:in:configuration:))

Identifies this view as the source of a navigation transition, such as a zoom transition.

[`protocol MatchedTransitionSourceConfiguration`](https://developer.apple.com/documentation/swiftui/matchedtransitionsourceconfiguration)

A configuration that defines the appearance of a matched transition source.

Current page is NavigationTransition

## SwiftUI Tab Initialization
[Skip Navigation](https://developer.apple.com/documentation/swiftui/tab/init(_:systemimage:role:content:)#app-main)

## Building Liquid Glass App
[Skip Navigation](https://developer.apple.com/documentation/swiftui/landmarks-building-an-app-with-liquid-glass#app-main)

## Liquid Glass Effects
[Skip Navigation](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views#app-main)

## Matched Geometry Properties
[Skip Navigation](https://developer.apple.com/documentation/swiftui/matchedgeometryproperties#app-main)

## SwiftUI Button Roles
[Skip Navigation](https://developer.apple.com/documentation/swiftui/buttonrole#app-main)

- [SwiftUI](https://developer.apple.com/documentation/swiftui)
- ButtonRole

Structure

# ButtonRole

A value that describes the purpose of a button.

iOS 15.0+iPadOS 15.0+Mac Catalyst 15.0+macOS 12.0+tvOS 15.0+visionOS 1.0+watchOS 8.0+

```
struct ButtonRole
```

## [Overview](https://developer.apple.com/documentation/swiftui/buttonrole\#overview)

A button role provides a description of a button’s purpose. For example, the [`destructive`](https://developer.apple.com/documentation/swiftui/buttonrole/destructive) role indicates that a button performs a destructive action, like delete user data:

```

```

## [Topics](https://developer.apple.com/documentation/swiftui/buttonrole\#topics)

### [Getting button roles](https://developer.apple.com/documentation/swiftui/buttonrole\#Getting-button-roles)

[`static let cancel: ButtonRole`](https://developer.apple.com/documentation/swiftui/buttonrole/cancel)

A role that indicates a button that cancels an operation.

[`static let destructive: ButtonRole`](https://developer.apple.com/documentation/swiftui/buttonrole/destructive)

A role that indicates a destructive button.

### [Type Properties](https://developer.apple.com/documentation/swiftui/buttonrole\#Type-Properties)

[`static let close: ButtonRole`](https://developer.apple.com/documentation/swiftui/buttonrole/close)

A role that indicates a button that closes the current operation.

Beta

[`static let confirm: ButtonRole`](https://developer.apple.com/documentation/swiftui/buttonrole/confirm)

A role that indicates a button that confirms an operation.

Beta

## [Relationships](https://developer.apple.com/documentation/swiftui/buttonrole\#relationships)

### [Conforms To](https://developer.apple.com/documentation/swiftui/buttonrole\#conforms-to)

- [`Equatable`](https://developer.apple.com/documentation/Swift/Equatable)
- [`Sendable`](https://developer.apple.com/documentation/Swift/Sendable)
- [`SendableMetatype`](https://developer.apple.com/documentation/Swift/SendableMetatype)

## [See Also](https://developer.apple.com/documentation/swiftui/buttonrole\#see-also)

### [Creating buttons](https://developer.apple.com/documentation/swiftui/buttonrole\#Creating-buttons)

[`struct Button`](https://developer.apple.com/documentation/swiftui/button)

A control that initiates an action.

[`func buttonStyle(_:)`](https://developer.apple.com/documentation/swiftui/view/buttonstyle(_:))

Sets the style for buttons within this view to a button style with a custom appearance and standard interaction behavior.

[`func buttonBorderShape(ButtonBorderShape) -> some View`](https://developer.apple.com/documentation/swiftui/view/buttonbordershape(_:))

Sets the border shape for buttons in this view.

[`func buttonRepeatBehavior(ButtonRepeatBehavior) -> some View`](https://developer.apple.com/documentation/swiftui/view/buttonrepeatbehavior(_:))

Sets whether buttons in this view should repeatedly trigger their actions on prolonged interactions.

[`var buttonRepeatBehavior: ButtonRepeatBehavior`](https://developer.apple.com/documentation/swiftui/environmentvalues/buttonrepeatbehavior)

Whether buttons with this associated environment should repeatedly trigger their actions on prolonged interactions.

[`struct ButtonBorderShape`](https://developer.apple.com/documentation/swiftui/buttonbordershape)

A shape used to draw a button’s border.

[`struct ButtonRepeatBehavior`](https://developer.apple.com/documentation/swiftui/buttonrepeatbehavior)

The options for controlling the repeatability of button actions.

[`struct ButtonSizing`](https://developer.apple.com/documentation/swiftui/buttonsizing) Beta

Current page is ButtonRole

## Content Size Categories
[Skip Navigation](https://developer.apple.com/documentation/swiftui/contentsizecategory#app-main)

## SwiftUI Geometry Effects
[Skip Navigation](https://developer.apple.com/documentation/swiftui/geometryeffect#app-main)

## Text Selection in SwiftUI
[Skip Navigation](https://developer.apple.com/documentation/swiftui/textselectability#app-main)

- [SwiftUI](https://developer.apple.com/documentation/swiftui)
- TextSelectability

Protocol

# TextSelectability

A type that describes the ability to select text.

iOS 15.0+iPadOS 15.0+Mac Catalyst 15.0+macOS 12.0+visionOS 1.0+

```
protocol TextSelectability
```

## [Overview](https://developer.apple.com/documentation/swiftui/textselectability\#overview)

To configure whether people can select text in your app, use the [`textSelection(_:)`](https://developer.apple.com/documentation/swiftui/view/textselection(_:)) modifier, passing in a text selectability value like [`enabled`](https://developer.apple.com/documentation/swiftui/textselectability/enabled) or [`disabled`](https://developer.apple.com/documentation/swiftui/textselectability/disabled).

## [Topics](https://developer.apple.com/documentation/swiftui/textselectability\#topics)

### [Getting selectability options](https://developer.apple.com/documentation/swiftui/textselectability\#Getting-selectability-options)

[`static var enabled: EnabledTextSelectability`](https://developer.apple.com/documentation/swiftui/textselectability/enabled)

A selectability value that enables text selection by a person using your app.

[`static var disabled: DisabledTextSelectability`](https://developer.apple.com/documentation/swiftui/textselectability/disabled)

A selectability value that disables text selection by the person using your app.

### [Specifying selectability](https://developer.apple.com/documentation/swiftui/textselectability\#Specifying-selectability)

[`static var allowsSelection: Bool`](https://developer.apple.com/documentation/swiftui/textselectability/allowsselection)

A Boolean value that indicates whether the selectability type allows selection.

**Required**

### [Supporting types](https://developer.apple.com/documentation/swiftui/textselectability\#Supporting-types)

[`struct EnabledTextSelectability`](https://developer.apple.com/documentation/swiftui/enabledtextselectability)

A selectability type that enables text selection by the person using your app.

[`struct DisabledTextSelectability`](https://developer.apple.com/documentation/swiftui/disabledtextselectability)

A selectability type that disables text selection by the person using your app.

## [Relationships](https://developer.apple.com/documentation/swiftui/textselectability\#relationships)

### [Conforming Types](https://developer.apple.com/documentation/swiftui/textselectability\#conforming-types)

- [`DisabledTextSelectability`](https://developer.apple.com/documentation/swiftui/disabledtextselectability)
- [`EnabledTextSelectability`](https://developer.apple.com/documentation/swiftui/enabledtextselectability)

## [See Also](https://developer.apple.com/documentation/swiftui/textselectability\#see-also)

### [Selecting text](https://developer.apple.com/documentation/swiftui/textselectability\#Selecting-text)

[`func textSelection<S>(S) -> some View`](https://developer.apple.com/documentation/swiftui/view/textselection(_:))

Controls whether people can select text within this view.

[`struct TextSelection`](https://developer.apple.com/documentation/swiftui/textselection)

Represents a selection of text.

[`func textSelectionAffinity(TextSelectionAffinity) -> some View`](https://developer.apple.com/documentation/swiftui/view/textselectionaffinity(_:))

Sets the direction of a selection or cursor relative to a text character.

[`var textSelectionAffinity: TextSelectionAffinity`](https://developer.apple.com/documentation/swiftui/environmentvalues/textselectionaffinity)

A representation of the direction or association of a selection or cursor relative to a text character. This concept becomes much more prominent when dealing with bidirectional text (text that contains both LTR and RTL scripts, like English and Arabic combined).

[`enum TextSelectionAffinity`](https://developer.apple.com/documentation/swiftui/textselectionaffinity)

A representation of the direction or association of a selection or cursor relative to a text character. This concept becomes much more prominent when dealing with bidirectional text (text that contains both LTR and RTL scripts, like English and Arabic combined).

[`struct AttributedTextSelection`](https://developer.apple.com/documentation/swiftui/attributedtextselection)

Represents a selection of attributed text.

Beta

Current page is TextSelectability

## SwiftUI Horizontal Alignment
[Skip Navigation](https://developer.apple.com/documentation/swiftui/horizontalalignment#app-main)

## SwiftUI HSplitView Guide
[Skip Navigation](https://developer.apple.com/documentation/swiftui/hsplitview#app-main)

## SwiftUI Circular Gauge
[Skip Navigation](https://developer.apple.com/documentation/swiftui/accessorycircularcapacitygaugestyle#app-main)

## Scroll Indicator Visibility
[Skip Navigation](https://developer.apple.com/documentation/swiftui/scrollindicatorvisibility#app-main)

- [SwiftUI](https://developer.apple.com/documentation/swiftui)
- ScrollIndicatorVisibility

Structure

# ScrollIndicatorVisibility

The visibility of scroll indicators of a UI element.

iOS 16.0+iPadOS 16.0+Mac Catalyst 16.0+macOS 13.0+tvOS 16.0+visionOS 1.0+watchOS 9.0+

```
struct ScrollIndicatorVisibility
```

## [Overview](https://developer.apple.com/documentation/swiftui/scrollindicatorvisibility\#overview)

Pass a value of this type to the [`scrollIndicators(_:axes:)`](https://developer.apple.com/documentation/swiftui/view/scrollindicators(_:axes:)) method to specify the preferred scroll indicator visibility of a view hierarchy.

## [Topics](https://developer.apple.com/documentation/swiftui/scrollindicatorvisibility\#topics)

### [Getting visibilties](https://developer.apple.com/documentation/swiftui/scrollindicatorvisibility\#Getting-visibilties)

[`static var automatic: ScrollIndicatorVisibility`](https://developer.apple.com/documentation/swiftui/scrollindicatorvisibility/automatic)

Scroll indicator visibility depends on the policies of the component accepting the visibility configuration.

[`static var hidden: ScrollIndicatorVisibility`](https://developer.apple.com/documentation/swiftui/scrollindicatorvisibility/hidden)

Hide the scroll indicators.

[`static var never: ScrollIndicatorVisibility`](https://developer.apple.com/documentation/swiftui/scrollindicatorvisibility/never)

Scroll indicators should never be visible.

[`static var visible: ScrollIndicatorVisibility`](https://developer.apple.com/documentation/swiftui/scrollindicatorvisibility/visible)

Show the scroll indicators.

## [Relationships](https://developer.apple.com/documentation/swiftui/scrollindicatorvisibility\#relationships)

### [Conforms To](https://developer.apple.com/documentation/swiftui/scrollindicatorvisibility\#conforms-to)

- [`Copyable`](https://developer.apple.com/documentation/Swift/Copyable)
- [`Equatable`](https://developer.apple.com/documentation/Swift/Equatable)

## [See Also](https://developer.apple.com/documentation/swiftui/scrollindicatorvisibility\#see-also)

### [Showing scroll indicators](https://developer.apple.com/documentation/swiftui/scrollindicatorvisibility\#Showing-scroll-indicators)

[`func scrollIndicatorsFlash(onAppear: Bool) -> some View`](https://developer.apple.com/documentation/swiftui/view/scrollindicatorsflash(onappear:))

Flashes the scroll indicators of a scrollable view when it appears.

[`func scrollIndicatorsFlash(trigger: some Equatable) -> some View`](https://developer.apple.com/documentation/swiftui/view/scrollindicatorsflash(trigger:))

Flashes the scroll indicators of scrollable views when a value changes.

[`func scrollIndicators(ScrollIndicatorVisibility, axes: Axis.Set) -> some View`](https://developer.apple.com/documentation/swiftui/view/scrollindicators(_:axes:))

Sets the visibility of scroll indicators within this view.

[`var horizontalScrollIndicatorVisibility: ScrollIndicatorVisibility`](https://developer.apple.com/documentation/swiftui/environmentvalues/horizontalscrollindicatorvisibility)

The visibility to apply to scroll indicators of any horizontally scrollable content.

[`var verticalScrollIndicatorVisibility: ScrollIndicatorVisibility`](https://developer.apple.com/documentation/swiftui/environmentvalues/verticalscrollindicatorvisibility)

The visiblity to apply to scroll indicators of any vertically scrollable content.

Current page is ScrollIndicatorVisibility

## SwiftUI Table Styles
[Skip Navigation](https://developer.apple.com/documentation/swiftui/tablestyleconfiguration#app-main)

## SwiftUI Placeholder Content
[Skip Navigation](https://developer.apple.com/documentation/swiftui/placeholdercontentview#app-main)

## NSHostingMenu Guide
[Skip Navigation](https://developer.apple.com/documentation/swiftui/nshostingmenu#app-main)

## SwiftUI Size Class Guide
[Skip Navigation](https://developer.apple.com/documentation/swiftui/userinterfacesizeclass#app-main)

## TVOS Media Catalog App
[Skip Navigation](https://developer.apple.com/documentation/swiftui/creating-a-tvos-media-catalog-app-in-swiftui#app-main)

## SwiftUI ScenePhase Guide
[Skip Navigation](https://developer.apple.com/documentation/swiftui/environmentvalues/scenephase#app-main)

## Text Input and Output
[Skip Navigation](https://developer.apple.com/documentation/swiftui/text-input-and-output#app-main)

Collection

- [SwiftUI](https://developer.apple.com/documentation/swiftui)
- Text input and output

API Collection

# Text input and output

Display formatted text and get text input from the user.

## [Overview](https://developer.apple.com/documentation/swiftui/text-input-and-output\#Overview)

To display read-only text, or read-only text paired with an image, use the built-in [`Text`](https://developer.apple.com/documentation/swiftui/text) or [`Label`](https://developer.apple.com/documentation/swiftui/label) views, respectively. When you need to collect text input from the user, use an appropriate text input view, like [`TextField`](https://developer.apple.com/documentation/swiftui/textfield) or [`TextEditor`](https://developer.apple.com/documentation/swiftui/texteditor).

![](https://docs-assets.developer.apple.com/published/a8d0f352ff6dabd1c3d1e3fdfb577250/text-input-and-output-hero%402x.png)

You add view modifiers to control the text’s font, selectability, alignment, layout direction, and so on. These modifiers also affect other views that display text, like the labels on controls, even if you don’t define an explicit [`Text`](https://developer.apple.com/documentation/swiftui/text) view.

For design guidance, see [Typography](https://developer.apple.com/design/Human-Interface-Guidelines/typography) in the Human Interface Guidelines.

## [Topics](https://developer.apple.com/documentation/swiftui/text-input-and-output\#topics)

### [Displaying text](https://developer.apple.com/documentation/swiftui/text-input-and-output\#Displaying-text)

[`struct Text`](https://developer.apple.com/documentation/swiftui/text)

A view that displays one or more lines of read-only text.

[`struct Label`](https://developer.apple.com/documentation/swiftui/label)

A standard label for user interface items, consisting of an icon with a title.

[`func labelStyle<S>(S) -> some View`](https://developer.apple.com/documentation/swiftui/view/labelstyle(_:))

Sets the style for labels within this view.

### [Getting text input](https://developer.apple.com/documentation/swiftui/text-input-and-output\#Getting-text-input)

[Building rich SwiftUI text experiences](https://developer.apple.com/documentation/swiftui/building-rich-swiftui-text-experiences)

Build an editor for formatted text using SwiftUI text editor views and attributed strings.

[`struct TextField`](https://developer.apple.com/documentation/swiftui/textfield)

A control that displays an editable text interface.

[`func textFieldStyle<S>(S) -> some View`](https://developer.apple.com/documentation/swiftui/view/textfieldstyle(_:))

Sets the style for text fields within this view.

[`struct SecureField`](https://developer.apple.com/documentation/swiftui/securefield)

A control into which people securely enter private text.

[`struct TextEditor`](https://developer.apple.com/documentation/swiftui/texteditor)

A view that can display and edit long-form text.

### [Selecting text](https://developer.apple.com/documentation/swiftui/text-input-and-output\#Selecting-text)

[`func textSelection<S>(S) -> some View`](https://developer.apple.com/documentation/swiftui/view/textselection(_:))

Controls whether people can select text within this view.

[`protocol TextSelectability`](https://developer.apple.com/documentation/swiftui/textselectability)

A type that describes the ability to select text.

[`struct TextSelection`](https://developer.apple.com/documentation/swiftui/textselection)

Represents a selection of text.

[`func textSelectionAffinity(TextSelectionAffinity) -> some View`](https://developer.apple.com/documentation/swiftui/view/textselectionaffinity(_:))

Sets the direction of a selection or cursor relative to a text character.

[`var textSelectionAffinity: TextSelectionAffinity`](https://developer.apple.com/documentation/swiftui/environmentvalues/textselectionaffinity)

A representation of the direction or association of a selection or cursor relative to a text character. This concept becomes much more prominent when dealing with bidirectional text (text that contains both LTR and RTL scripts, like English and Arabic combined).

[`enum TextSelectionAffinity`](https://developer.apple.com/documentation/swiftui/textselectionaffinity)

A representation of the direction or association of a selection or cursor relative to a text character. This concept becomes much more prominent when dealing with bidirectional text (text that contains both LTR and RTL scripts, like English and Arabic combined).

[`struct AttributedTextSelection`](https://developer.apple.com/documentation/swiftui/attributedtextselection)

Represents a selection of attributed text.

Beta

### [Setting a font](https://developer.apple.com/documentation/swiftui/text-input-and-output\#Setting-a-font)

[Applying custom fonts to text](https://developer.apple.com/documentation/swiftui/applying-custom-fonts-to-text)

Add and use a font in your app that scales with Dynamic Type.

[`func font(Font?) -> some View`](https://developer.apple.com/documentation/swiftui/view/font(_:))

Sets the default font for text in this view.

[`func fontDesign(Font.Design?) -> some View`](https://developer.apple.com/documentation/swiftui/view/fontdesign(_:))

Sets the font design of the text in this view.

[`func fontWeight(Font.Weight?) -> some View`](https://developer.apple.com/documentation/swiftui/view/fontweight(_:))

Sets the font weight of the text in this view.

[`func fontWidth(Font.Width?) -> some View`](https://developer.apple.com/documentation/swiftui/view/fontwidth(_:))

Sets the font width of the text in this view.

[`var font: Font?`](https://developer.apple.com/documentation/swiftui/environmentvalues/font)

The default font of this environment.

[`struct Font`](https://developer.apple.com/documentation/swiftui/font)

An environment-dependent font.

### [Adjusting text size](https://developer.apple.com/documentation/swiftui/text-input-and-output\#Adjusting-text-size)

[`func textScale(Text.Scale, isEnabled: Bool) -> some View`](https://developer.apple.com/documentation/swiftui/view/textscale(_:isenabled:))

Applies a text scale to text in the view.

[`func dynamicTypeSize(_:)`](https://developer.apple.com/documentation/swiftui/view/dynamictypesize(_:))

Sets the Dynamic Type size within the view to the given value.

[`var dynamicTypeSize: DynamicTypeSize`](https://developer.apple.com/documentation/swiftui/environmentvalues/dynamictypesize)

The current Dynamic Type size.

[`enum DynamicTypeSize`](https://developer.apple.com/documentation/swiftui/dynamictypesize)

A Dynamic Type size, which specifies how large scalable content should be.

[`struct ScaledMetric`](https://developer.apple.com/documentation/swiftui/scaledmetric)

A dynamic property that scales a numeric value.

[`protocol TextVariantPreference`](https://developer.apple.com/documentation/swiftui/textvariantpreference)

A protocol for controlling the size variant of text views.

[`struct FixedTextVariant`](https://developer.apple.com/documentation/swiftui/fixedtextvariant)

The default text variant preference that chooses the largest available variant.

[`struct SizeDependentTextVariant`](https://developer.apple.com/documentation/swiftui/sizedependenttextvariant)

The size dependent variant preference allows the text to take the available space into account when choosing the variant to display.

### [Controlling text style](https://developer.apple.com/documentation/swiftui/text-input-and-output\#Controlling-text-style)

[`func bold(Bool) -> some View`](https://developer.apple.com/documentation/swiftui/view/bold(_:))

Applies a bold font weight to the text in this view.

[`func italic(Bool) -> some View`](https://developer.apple.com/documentation/swiftui/view/italic(_:))

Applies italics to the text in this view.

[`func underline(Bool, pattern: Text.LineStyle.Pattern, color: Color?) -> some View`](https://developer.apple.com/documentation/swiftui/view/underline(_:pattern:color:))

Applies an underline to the text in this view.

[`func strikethrough(Bool, pattern: Text.LineStyle.Pattern, color: Color?) -> some View`](https://developer.apple.com/documentation/swiftui/view/strikethrough(_:pattern:color:))

Applies a strikethrough to the text in this view.

[`func textCase(Text.Case?) -> some View`](https://developer.apple.com/documentation/swiftui/view/textcase(_:))

Sets a transform for the case of the text contained in this view when displayed.

[`var textCase: Text.Case?`](https://developer.apple.com/documentation/swiftui/environmentvalues/textcase)

A stylistic override to transform the case of `Text` when displayed, using the environment’s locale.

[`func monospaced(Bool) -> some View`](https://developer.apple.com/documentation/swiftui/view/monospaced(_:))

Modifies the fonts of all child views to use the fixed-width variant of the current font, if possible.

[`func monospacedDigit() -> some View`](https://developer.apple.com/documentation/swiftui/view/monospaceddigit())

Modifies the fonts of all child views to use fixed-width digits, if possible, while leaving other characters proportionally spaced.

[`protocol AttributedTextFormattingDefinition`](https://developer.apple.com/documentation/swiftui/attributedtextformattingdefinition)

A protocol for defining how text can be styled in a certain context, e.g. a `TextEditor`.

Beta

[`protocol AttributedTextValueConstraint`](https://developer.apple.com/documentation/swiftui/attributedtextvalueconstraint)

A protocol for defining a constraint on the value of a certain attribute.

Beta

[`enum AttributedTextFormatting`](https://developer.apple.com/documentation/swiftui/attributedtextformatting)

A namespace for types related to attributed text formatting definitions.

Beta

### [Managing text layout](https://developer.apple.com/documentation/swiftui/text-input-and-output\#Managing-text-layout)

[`func truncationMode(Text.TruncationMode) -> some View`](https://developer.apple.com/documentation/swiftui/view/truncationmode(_:))

Sets the truncation mode for lines of text that are too long to fit in the available space.

[`var truncationMode: Text.TruncationMode`](https://developer.apple.com/documentation/swiftui/environmentvalues/truncationmode)

A value that indicates how the layout truncates the last line of text to fit into the available space.

[`func allowsTightening(Bool) -> some View`](https://developer.apple.com/documentation/swiftui/view/allowstightening(_:))

Sets whether text in this view can compress the space between characters when necessary to fit text in a line.

[`var allowsTightening: Bool`](https://developer.apple.com/documentation/swiftui/environmentvalues/allowstightening)

A Boolean value that indicates whether inter-character spacing should tighten to fit the text into the available space.

[`func minimumScaleFactor(CGFloat) -> some View`](https://developer.apple.com/documentation/swiftui/view/minimumscalefactor(_:))

Sets the minimum amount that text in this view scales down to fit in the available space.

[`var minimumScaleFactor: CGFloat`](https://developer.apple.com/documentation/swiftui/environmentvalues/minimumscalefactor)

The minimum permissible proportion to shrink the font size to fit the text into the available space.

[`func baselineOffset(CGFloat) -> some View`](https://developer.apple.com/documentation/swiftui/view/baselineoffset(_:))

Sets the vertical offset for the text relative to its baseline in this view.

[`func kerning(CGFloat) -> some View`](https://developer.apple.com/documentation/swiftui/view/kerning(_:))

Sets the spacing, or kerning, between characters for the text in this view.

[`func tracking(CGFloat) -> some View`](https://developer.apple.com/documentation/swiftui/view/tracking(_:))

Sets the tracking for the text in this view.

[`func flipsForRightToLeftLayoutDirection(Bool) -> some View`](https://developer.apple.com/documentation/swiftui/view/flipsforrighttoleftlayoutdirection(_:))

Sets whether this view mirrors its contents horizontally when the layout direction is right-to-left.

[`enum TextAlignment`](https://developer.apple.com/documentation/swiftui/textalignment)

An alignment position for text along the horizontal axis.

### [Rendering text](https://developer.apple.com/documentation/swiftui/text-input-and-output\#Rendering-text)

[Creating visual effects with SwiftUI](https://developer.apple.com/documentation/swiftui/creating-visual-effects-with-swiftui)

Add scroll effects, rich color treatments, custom transitions, and advanced effects using shaders and a text renderer.

[`protocol TextAttribute`](https://developer.apple.com/documentation/swiftui/textattribute)

A value that you can attach to text views and that text renderers can query.

[`func textRenderer<T>(T) -> some View`](https://developer.apple.com/documentation/swiftui/view/textrenderer(_:))

Returns a new view such that any text views within it will use `renderer` to draw themselves.

[`protocol TextRenderer`](https://developer.apple.com/documentation/swiftui/textrenderer)

A value that can replace the default text view rendering behavior.

[`struct TextProxy`](https://developer.apple.com/documentation/swiftui/textproxy)

A proxy for a text view that custom text renderers use.

### [Limiting line count for multiline text](https://developer.apple.com/documentation/swiftui/text-input-and-output\#Limiting-line-count-for-multiline-text)

[`func lineLimit(_:)`](https://developer.apple.com/documentation/swiftui/view/linelimit(_:))

Sets to a closed range the number of lines that text can occupy in this view.

[`func lineLimit(Int, reservesSpace: Bool) -> some View`](https://developer.apple.com/documentation/swiftui/view/linelimit(_:reservesspace:))

Sets a limit for the number of lines text can occupy in this view.

[`var lineLimit: Int?`](https://developer.apple.com/documentation/swiftui/environmentvalues/linelimit)

The maximum number of lines that text can occupy in a view.

### [Formatting multiline text](https://developer.apple.com/documentation/swiftui/text-input-and-output\#Formatting-multiline-text)

[`func lineSpacing(CGFloat) -> some View`](https://developer.apple.com/documentation/swiftui/view/linespacing(_:))

Sets the amount of space between lines of text in this view.

[`var lineSpacing: CGFloat`](https://developer.apple.com/documentation/swiftui/environmentvalues/linespacing)

The distance in points between the bottom of one line fragment and the top of the next.

[`func multilineTextAlignment(TextAlignment) -> some View`](https://developer.apple.com/documentation/swiftui/view/multilinetextalignment(_:))

Sets the alignment of a text view that contains multiple lines of text.

[`var multilineTextAlignment: TextAlignment`](https://developer.apple.com/documentation/swiftui/environmentvalues/multilinetextalignment)

An environment value that indicates how a text view aligns its lines when the content wraps or contains newlines.

### [Formatting date and time](https://developer.apple.com/documentation/swiftui/text-input-and-output\#Formatting-date-and-time)

[`enum SystemFormatStyle`](https://developer.apple.com/documentation/swiftui/systemformatstyle)

A namespace for format styles that implement designs used across Apple’s platformes.

[`struct TimeDataSource`](https://developer.apple.com/documentation/swiftui/timedatasource)

A source of time related data.

### [Managing text entry](https://developer.apple.com/documentation/swiftui/text-input-and-output\#Managing-text-entry)

[`func autocorrectionDisabled(Bool) -> some View`](https://developer.apple.com/documentation/swiftui/view/autocorrectiondisabled(_:))

Sets whether to disable autocorrection for this view.

[`var autocorrectionDisabled: Bool`](https://developer.apple.com/documentation/swiftui/environmentvalues/autocorrectiondisabled)

A Boolean value that determines whether the view hierarchy has auto-correction enabled.

[`func keyboardType(UIKeyboardType) -> some View`](https://developer.apple.com/documentation/swiftui/view/keyboardtype(_:))

Sets the keyboard type for this view.

[`func scrollDismissesKeyboard(ScrollDismissesKeyboardMode) -> some View`](https://developer.apple.com/documentation/swiftui/view/scrolldismisseskeyboard(_:))

Configures the behavior in which scrollable content interacts with the software keyboard.

[`func textContentType(_:)`](https://developer.apple.com/documentation/swiftui/view/textcontenttype(_:))

Sets the text content type for this view, which the system uses to offer suggestions while the user enters text on macOS.

[`func textInputAutocapitalization(TextInputAutocapitalization?) -> some View`](https://developer.apple.com/documentation/swiftui/view/textinputautocapitalization(_:))

Sets how often the shift key in the keyboard is automatically enabled.

[`struct TextInputAutocapitalization`](https://developer.apple.com/documentation/swiftui/textinputautocapitalization)

The kind of autocapitalization behavior applied during text input.

[`func textInputCompletion(String) -> some View`](https://developer.apple.com/documentation/swiftui/view/textinputcompletion(_:))

Associates a fully formed string with the value of this view when used as a text input suggestion

[`func textInputSuggestions<S>(() -> S) -> some View`](https://developer.apple.com/documentation/swiftui/view/textinputsuggestions(_:))

Configures the text input suggestions for this view.

[`func textInputSuggestions<Data, Content>(Data, content: (Data.Element) -> Content) -> some View`](https://developer.apple.com/documentation/swiftui/view/textinputsuggestions(_:content:))

Configures the text input suggestions for this view.

[`func textInputSuggestions<Data, ID, Content>(Data, id: KeyPath<Data.Element, ID>, content: (Data.Element) -> Content) -> some View`](https://developer.apple.com/documentation/swiftui/view/textinputsuggestions(_:id:content:))

Configures the text input suggestions for this view.

[`func textContentType(WKTextContentType?) -> some View`](https://developer.apple.com/documentation/swiftui/view/textcontenttype(_:)-4dqqb)

Sets the text content type for this view, which the system uses to offer suggestions while the user enters text on a watchOS device.

[`func textContentType(NSTextContentType?) -> some View`](https://developer.apple.com/documentation/swiftui/view/textcontenttype(_:)-6fic1)

Sets the text content type for this view, which the system uses to offer suggestions while the user enters text on macOS.

[`func textContentType(UITextContentType?) -> some View`](https://developer.apple.com/documentation/swiftui/view/textcontenttype(_:)-ufdv)

Sets the text content type for this view, which the system uses to offer suggestions while the user enters text on an iOS or tvOS device.

[`struct TextInputFormattingControlPlacement`](https://developer.apple.com/documentation/swiftui/textinputformattingcontrolplacement)

A structure defining the system text formatting controls available on each platform.

Beta

### [Dictating text](https://developer.apple.com/documentation/swiftui/text-input-and-output\#Dictating-text)

[`func searchDictationBehavior(TextInputDictationBehavior) -> some View`](https://developer.apple.com/documentation/swiftui/view/searchdictationbehavior(_:))

Configures the dictation behavior for any search fields configured by the searchable modifier.

[`struct TextInputDictationActivation`](https://developer.apple.com/documentation/swiftui/textinputdictationactivation)

[`struct TextInputDictationBehavior`](https://developer.apple.com/documentation/swiftui/textinputdictationbehavior)

### [Configuring the Writing Tools behavior](https://developer.apple.com/documentation/swiftui/text-input-and-output\#Configuring-the-Writing-Tools-behavior)

[`func writingToolsBehavior(WritingToolsBehavior) -> some View`](https://developer.apple.com/documentation/swiftui/view/writingtoolsbehavior(_:))

Specifies the Writing Tools behavior for text and text input in the environment.

[`struct WritingToolsBehavior`](https://developer.apple.com/documentation/swiftui/writingtoolsbehavior)

The Writing Tools editing experience for text and text input.

### [Specifying text equivalents](https://developer.apple.com/documentation/swiftui/text-input-and-output\#Specifying-text-equivalents)

[`func typeSelectEquivalent(_:)`](https://developer.apple.com/documentation/swiftui/view/typeselectequivalent(_:))

Sets an explicit type select equivalent text in a collection, such as a list or table.

### [Localizing text](https://developer.apple.com/documentation/swiftui/text-input-and-output\#Localizing-text)

[Preparing views for localization](https://developer.apple.com/documentation/swiftui/preparing-views-for-localization)

Specify hints and add strings to localize your SwiftUI views.

[`struct LocalizedStringKey`](https://developer.apple.com/documentation/swiftui/localizedstringkey)

The key used to look up an entry in a strings file or strings dictionary file.

[`var locale: Locale`](https://developer.apple.com/documentation/swiftui/environmentvalues/locale)

The current locale that views should use.

[`func typesettingLanguage(_:isEnabled:)`](https://developer.apple.com/documentation/swiftui/view/typesettinglanguage(_:isenabled:))

Specifies the language for typesetting.

[`struct TypesettingLanguage`](https://developer.apple.com/documentation/swiftui/typesettinglanguage)

Defines how typesetting language is determined for text.

### [Deprecated types](https://developer.apple.com/documentation/swiftui/text-input-and-output\#Deprecated-types)

[`enum ContentSizeCategory`](https://developer.apple.com/documentation/swiftui/contentsizecategory)

The sizes that you can specify for content.

Deprecated

## [See Also](https://developer.apple.com/documentation/swiftui/text-input-and-output\#see-also)

### [Views](https://developer.apple.com/documentation/swiftui/text-input-and-output\#Views)

[API Reference\\
View fundamentals](https://developer.apple.com/documentation/swiftui/view-fundamentals)

Define the visual elements of your app using a hierarchy of views.

[API Reference\\
View configuration](https://developer.apple.com/documentation/swiftui/view-configuration)

Adjust the characteristics of views in a hierarchy.

[API Reference\\
View styles](https://developer.apple.com/documentation/swiftui/view-styles)

Apply built-in and custom appearances and behaviors to different types of views.

[API Reference\\
Animations](https://developer.apple.com/documentation/swiftui/animations)

Create smooth visual updates in response to state changes.

[API Reference\\
Images](https://developer.apple.com/documentation/swiftui/images)

Add images and symbols to your app’s user interface.

[API Reference\\
Controls and indicators](https://developer.apple.com/documentation/swiftui/controls-and-indicators)

Display values and get user selections.

[API Reference\\
Menus and commands](https://developer.apple.com/documentation/swiftui/menus-and-commands)

Provide space-efficient, context-dependent access to commands and controls.

[API Reference\\
Shapes](https://developer.apple.com/documentation/swiftui/shapes)

Trace and fill built-in and custom shapes with a color, gradient, or other pattern.

[API Reference\\
Drawing and graphics](https://developer.apple.com/documentation/swiftui/drawing-and-graphics)

Enhance your views with graphical effects and customized drawings.

Current page is Text input and output

## Open Immersive Space
[Skip Navigation](https://developer.apple.com/documentation/swiftui/environmentvalues/openimmersivespace#app-main)

## SwiftUI Accessible Descriptions
[Skip Navigation](https://developer.apple.com/documentation/swiftui/accessible-descriptions#app-main)

## SwiftUI Toolbars
[Skip Navigation](https://developer.apple.com/documentation/swiftui/toolbars#app-main)

Collection

- [SwiftUI](https://developer.apple.com/documentation/swiftui)
- Toolbars

API Collection

# Toolbars

Provide immediate access to frequently used commands and controls.

## [Overview](https://developer.apple.com/documentation/swiftui/toolbars\#Overview)

The system might present toolbars above or below your app’s content, depending on the platform and the context.

![](https://docs-assets.developer.apple.com/published/16bd7e535a587b44ad58a35c066192d9/toolbars-hero%402x.png)

Add items to a toolbar by applying the [`toolbar(content:)`](https://developer.apple.com/documentation/swiftui/view/toolbar(content:)) view modifier to a view in your app. You can also configure the toolbar using view modifiers. For example, you can set the visibility of a toolbar with the [`toolbar(_:for:)`](https://developer.apple.com/documentation/swiftui/view/toolbar(_:for:)) modifier.

For design guidance, see [Toolbars](https://developer.apple.com/design/Human-Interface-Guidelines/toolbars) in the Human Interface Guidelines.

## [Topics](https://developer.apple.com/documentation/swiftui/toolbars\#topics)

### [Populating a toolbar](https://developer.apple.com/documentation/swiftui/toolbars\#Populating-a-toolbar)

[`func toolbar(content:)`](https://developer.apple.com/documentation/swiftui/view/toolbar(content:))

Populates the toolbar or navigation bar with the specified items.

[`struct ToolbarItem`](https://developer.apple.com/documentation/swiftui/toolbaritem)

A model that represents an item which can be placed in the toolbar or navigation bar.

[`struct ToolbarItemGroup`](https://developer.apple.com/documentation/swiftui/toolbaritemgroup)

A model that represents a group of `ToolbarItem` s which can be placed in the toolbar or navigation bar.

[`struct ToolbarItemPlacement`](https://developer.apple.com/documentation/swiftui/toolbaritemplacement)

A structure that defines the placement of a toolbar item.

[`protocol ToolbarContent`](https://developer.apple.com/documentation/swiftui/toolbarcontent)

Conforming types represent items that can be placed in various locations in a toolbar.

[`struct ToolbarContentBuilder`](https://developer.apple.com/documentation/swiftui/toolbarcontentbuilder)

Constructs a toolbar item set from multi-expression closures.

[`struct ToolbarSpacer`](https://developer.apple.com/documentation/swiftui/toolbarspacer)

A standard space item in toolbars.

Beta

[`struct DefaultToolbarItem`](https://developer.apple.com/documentation/swiftui/defaulttoolbaritem)

A toolbar item that represents a system component.

Beta

### [Populating a customizable toolbar](https://developer.apple.com/documentation/swiftui/toolbars\#Populating-a-customizable-toolbar)

[`func toolbar<Content>(id: String, content: () -> Content) -> some View`](https://developer.apple.com/documentation/swiftui/view/toolbar(id:content:))

Populates the toolbar or navigation bar with the specified items, allowing for user customization.

[`protocol CustomizableToolbarContent`](https://developer.apple.com/documentation/swiftui/customizabletoolbarcontent)

Conforming types represent items that can be placed in various locations in a customizable toolbar.

[`struct ToolbarCustomizationBehavior`](https://developer.apple.com/documentation/swiftui/toolbarcustomizationbehavior)

The customization behavior of customizable toolbar content.

[`struct ToolbarCustomizationOptions`](https://developer.apple.com/documentation/swiftui/toolbarcustomizationoptions)

Options that influence the default customization behavior of customizable toolbar content.

[`struct SearchToolbarBehavior`](https://developer.apple.com/documentation/swiftui/searchtoolbarbehavior)

The behavior of a search field in a toolbar.

Beta

### [Removing default items](https://developer.apple.com/documentation/swiftui/toolbars\#Removing-default-items)

[`func toolbar(removing: ToolbarDefaultItemKind?) -> some View`](https://developer.apple.com/documentation/swiftui/view/toolbar(removing:))

Remove a toolbar item present by default

[`struct ToolbarDefaultItemKind`](https://developer.apple.com/documentation/swiftui/toolbardefaultitemkind)

A kind of toolbar item a `View` adds by default.

### [Setting toolbar visibility](https://developer.apple.com/documentation/swiftui/toolbars\#Setting-toolbar-visibility)

[`func toolbar(Visibility, for: ToolbarPlacement...) -> some View`](https://developer.apple.com/documentation/swiftui/view/toolbar(_:for:))

Specifies the visibility of a bar managed by SwiftUI.

[`func toolbarVisibility(Visibility, for: ToolbarPlacement...) -> some View`](https://developer.apple.com/documentation/swiftui/view/toolbarvisibility(_:for:))

Specifies the visibility of a bar managed by SwiftUI.

[`func toolbarBackgroundVisibility(Visibility, for: ToolbarPlacement...) -> some View`](https://developer.apple.com/documentation/swiftui/view/toolbarbackgroundvisibility(_:for:))

Specifies the preferred visibility of backgrounds on a bar managed by SwiftUI.

[`struct ToolbarPlacement`](https://developer.apple.com/documentation/swiftui/toolbarplacement)

The placement of a toolbar.

[`struct ContentToolbarPlacement`](https://developer.apple.com/documentation/swiftui/contenttoolbarplacement)

### [Specifying the role of toolbar content](https://developer.apple.com/documentation/swiftui/toolbars\#Specifying-the-role-of-toolbar-content)

[`func toolbarRole(ToolbarRole) -> some View`](https://developer.apple.com/documentation/swiftui/view/toolbarrole(_:))

Configures the semantic role for the content populating the toolbar.

[`struct ToolbarRole`](https://developer.apple.com/documentation/swiftui/toolbarrole)

The purpose of content that populates the toolbar.

### [Styling a toolbar](https://developer.apple.com/documentation/swiftui/toolbars\#Styling-a-toolbar)

[`func toolbarBackground(_:for:)`](https://developer.apple.com/documentation/swiftui/view/toolbarbackground(_:for:))

Specifies the preferred shape style of the background of a bar managed by SwiftUI.

[`func toolbarColorScheme(ColorScheme?, for: ToolbarPlacement...) -> some View`](https://developer.apple.com/documentation/swiftui/view/toolbarcolorscheme(_:for:))

Specifies the preferred color scheme of a bar managed by SwiftUI.

[`func toolbarForegroundStyle<S>(S, for: ToolbarPlacement...) -> some View`](https://developer.apple.com/documentation/swiftui/view/toolbarforegroundstyle(_:for:))

Specifies the preferred foreground style of bars managed by SwiftUI.

[`func windowToolbarStyle<S>(S) -> some Scene`](https://developer.apple.com/documentation/swiftui/scene/windowtoolbarstyle(_:))

Sets the style for the toolbar defined within this scene.

[`protocol WindowToolbarStyle`](https://developer.apple.com/documentation/swiftui/windowtoolbarstyle)

A specification for the appearance and behavior of a window’s toolbar.

[`var toolbarLabelStyle: ToolbarLabelStyle?`](https://developer.apple.com/documentation/swiftui/environmentvalues/toolbarlabelstyle)

The label style to apply to controls within a toolbar.

[`struct ToolbarLabelStyle`](https://developer.apple.com/documentation/swiftui/toolbarlabelstyle)

The label style of a toolbar.

[`struct SpacerSizing`](https://developer.apple.com/documentation/swiftui/spacersizing)

A type which defines how spacers should size themselves.

Beta

### [Configuring the toolbar title display mode](https://developer.apple.com/documentation/swiftui/toolbars\#Configuring-the-toolbar-title-display-mode)

[`func toolbarTitleDisplayMode(ToolbarTitleDisplayMode) -> some View`](https://developer.apple.com/documentation/swiftui/view/toolbartitledisplaymode(_:))

Configures the toolbar title display mode for this view.

[`struct ToolbarTitleDisplayMode`](https://developer.apple.com/documentation/swiftui/toolbartitledisplaymode)

A type that defines the behavior of title of a toolbar.

### [Setting the toolbar title menu](https://developer.apple.com/documentation/swiftui/toolbars\#Setting-the-toolbar-title-menu)

[`func toolbarTitleMenu<C>(content: () -> C) -> some View`](https://developer.apple.com/documentation/swiftui/view/toolbartitlemenu(content:))

Configure the title menu of a toolbar.

[`struct ToolbarTitleMenu`](https://developer.apple.com/documentation/swiftui/toolbartitlemenu)

The title menu of a toolbar.

### [Creating an ornament](https://developer.apple.com/documentation/swiftui/toolbars\#Creating-an-ornament)

[`func ornament(visibility:attachmentAnchor:contentAlignment:ornament:)`](https://developer.apple.com/documentation/swiftui/view/ornament(visibility:attachmentanchor:contentalignment:ornament:))

Presents an ornament.

[`struct OrnamentAttachmentAnchor`](https://developer.apple.com/documentation/swiftui/ornamentattachmentanchor)

An attachment anchor for an ornament.

## [See Also](https://developer.apple.com/documentation/swiftui/toolbars\#see-also)

### [App structure](https://developer.apple.com/documentation/swiftui/toolbars\#App-structure)

[API Reference\\
App organization](https://developer.apple.com/documentation/swiftui/app-organization)

Define the entry point and top-level structure of your app.

[API Reference\\
Scenes](https://developer.apple.com/documentation/swiftui/scenes)

Declare the user interface groupings that make up the parts of your app.

[API Reference\\
Windows](https://developer.apple.com/documentation/swiftui/windows)

Display user interface content in a window or a collection of windows.

[API Reference\\
Immersive spaces](https://developer.apple.com/documentation/swiftui/immersive-spaces)

Display unbounded content in a person’s surroundings.

[API Reference\\
Documents](https://developer.apple.com/documentation/swiftui/documents)

Enable people to open and manage documents.

[API Reference\\
Navigation](https://developer.apple.com/documentation/swiftui/navigation)

Enable people to move between different parts of your app’s view hierarchy within a scene.

[API Reference\\
Modal presentations](https://developer.apple.com/documentation/swiftui/modal-presentations)

Present content in a separate view that offers focused interaction.

[API Reference\\
Search](https://developer.apple.com/documentation/swiftui/search)

Enable people to search for text or other content within your app.

[API Reference\\
App extensions](https://developer.apple.com/documentation/swiftui/app-extensions)

Extend your app’s basic functionality to other parts of the system, like by adding a Widget.

Current page is Toolbars

## SwiftUI App Delegate Integration
[Skip Navigation](https://developer.apple.com/documentation/swiftui/wkapplicationdelegateadaptor#app-main)

## SwiftUI Clipboard Guide
[Skip Navigation](https://developer.apple.com/documentation/swiftui/clipboard#app-main)

## SwiftUI Gestures
[Skip Navigation](https://developer.apple.com/documentation/swiftui/gestures#app-main)

Collection

- [SwiftUI](https://developer.apple.com/documentation/swiftui)
- Gestures

API Collection

# Gestures

Define interactions from taps, clicks, and swipes to fine-grained gestures.

## [Overview](https://developer.apple.com/documentation/swiftui/gestures\#Overview)

Respond to gestures by adding gesture modifiers to your views. You can listen for taps, drags, pinches, and other standard gestures.

![](https://docs-assets.developer.apple.com/published/6a1478e9bc9c150def717738cb949d52/gestures-hero%402x.png)

You can also compose custom gestures from individual gestures using the [`simultaneously(with:)`](https://developer.apple.com/documentation/swiftui/gesture/simultaneously(with:)), [`sequenced(before:)`](https://developer.apple.com/documentation/swiftui/gesture/sequenced(before:)), or [`exclusively(before:)`](https://developer.apple.com/documentation/swiftui/gesture/exclusively(before:)) modifiers, or combine gestures with keyboard modifiers using the [`modifiers(_:)`](https://developer.apple.com/documentation/swiftui/gesture/modifiers(_:)) modifier.

For design guidance, see [Gestures](https://developer.apple.com/design/Human-Interface-Guidelines/gestures) in the Human Interface Guidelines.

## [Topics](https://developer.apple.com/documentation/swiftui/gestures\#topics)

### [Essentials](https://developer.apple.com/documentation/swiftui/gestures\#Essentials)

[Adding interactivity with gestures](https://developer.apple.com/documentation/swiftui/adding-interactivity-with-gestures)

Use gesture modifiers to add interactivity to your app.

### [Recognizing tap gestures](https://developer.apple.com/documentation/swiftui/gestures\#Recognizing-tap-gestures)

[`func onTapGesture(count: Int, perform: () -> Void) -> some View`](https://developer.apple.com/documentation/swiftui/view/ontapgesture(count:perform:))

Adds an action to perform when this view recognizes a tap gesture.

[`func onTapGesture(count:coordinateSpace:perform:)`](https://developer.apple.com/documentation/swiftui/view/ontapgesture(count:coordinatespace:perform:))

Adds an action to perform when this view recognizes a tap gesture, and provides the action with the location of the interaction.

[`struct TapGesture`](https://developer.apple.com/documentation/swiftui/tapgesture)

A gesture that recognizes one or more taps.

[`struct SpatialTapGesture`](https://developer.apple.com/documentation/swiftui/spatialtapgesture)

A gesture that recognizes one or more taps and reports their location.

### [Recognizing long press gestures](https://developer.apple.com/documentation/swiftui/gestures\#Recognizing-long-press-gestures)

[`func onLongPressGesture(minimumDuration: Double, maximumDistance: CGFloat, perform: () -> Void, onPressingChanged: ((Bool) -> Void)?) -> some View`](https://developer.apple.com/documentation/swiftui/view/onlongpressgesture(minimumduration:maximumdistance:perform:onpressingchanged:))

Adds an action to perform when this view recognizes a long press gesture.

[`func onLongPressGesture(minimumDuration: Double, perform: () -> Void, onPressingChanged: ((Bool) -> Void)?) -> some View`](https://developer.apple.com/documentation/swiftui/view/onlongpressgesture(minimumduration:perform:onpressingchanged:))

Adds an action to perform when this view recognizes a long press gesture.

[`func onLongTouchGesture(minimumDuration: Double, perform: () -> Void, onTouchingChanged: ((Bool) -> Void)?) -> some View`](https://developer.apple.com/documentation/swiftui/view/onlongtouchgesture(minimumduration:perform:ontouchingchanged:))

Adds an action to perform when this view recognizes a remote long touch gesture. A long touch gesture is when the finger is on the remote touch surface without actually pressing.

[`struct LongPressGesture`](https://developer.apple.com/documentation/swiftui/longpressgesture)

A gesture that succeeds when the user performs a long press.

### [Recognizing spatial events](https://developer.apple.com/documentation/swiftui/gestures\#Recognizing-spatial-events)

[`struct SpatialEventGesture`](https://developer.apple.com/documentation/swiftui/spatialeventgesture)

A gesture that provides information about ongoing spatial events like clicks and touches.

[`struct SpatialEventCollection`](https://developer.apple.com/documentation/swiftui/spatialeventcollection)

A collection of spatial input events that target a specific view.

[`enum Chirality`](https://developer.apple.com/documentation/swiftui/chirality)

The chirality, or handedness, of a pose.

### [Recognizing gestures that change over time](https://developer.apple.com/documentation/swiftui/gestures\#Recognizing-gestures-that-change-over-time)

[`func gesture(_:)`](https://developer.apple.com/documentation/swiftui/view/gesture(_:))

Attaches an [`NSGestureRecognizerRepresentable`](https://developer.apple.com/documentation/swiftui/nsgesturerecognizerrepresentable) to the view.

Beta

[`func gesture<T>(T, isEnabled: Bool) -> some View`](https://developer.apple.com/documentation/swiftui/view/gesture(_:isenabled:))

Attaches a gesture to the view with a lower precedence than gestures defined by the view.

[`func gesture<T>(T, name: String, isEnabled: Bool) -> some View`](https://developer.apple.com/documentation/swiftui/view/gesture(_:name:isenabled:))

Attaches a gesture to the view with a lower precedence than gestures defined by the view.

[`func gesture<T>(T, including: GestureMask) -> some View`](https://developer.apple.com/documentation/swiftui/view/gesture(_:including:))

Attaches a gesture to the view with a lower precedence than gestures defined by the view.

[`struct DragGesture`](https://developer.apple.com/documentation/swiftui/draggesture)

A dragging motion that invokes an action as the drag-event sequence changes.

[`struct WindowDragGesture`](https://developer.apple.com/documentation/swiftui/windowdraggesture)

A gesture that recognizes the motion of and handles dragging a window.

[`struct MagnifyGesture`](https://developer.apple.com/documentation/swiftui/magnifygesture)

A gesture that recognizes a magnification motion and tracks the amount of magnification.

[`struct RotateGesture`](https://developer.apple.com/documentation/swiftui/rotategesture)

A gesture that recognizes a rotation motion and tracks the angle of the rotation.

[`struct RotateGesture3D`](https://developer.apple.com/documentation/swiftui/rotategesture3d)

A gesture that recognizes 3D rotation motion and tracks the angle and axis of the rotation.

[`struct GestureMask`](https://developer.apple.com/documentation/swiftui/gesturemask)

Options that control how adding a gesture to a view affects other gestures recognized by the view and its subviews.

### [Recognizing Apple Pencil gestures](https://developer.apple.com/documentation/swiftui/gestures\#Recognizing-Apple-Pencil-gestures)

[`func onPencilDoubleTap(perform: (PencilDoubleTapGestureValue) -> Void) -> some View`](https://developer.apple.com/documentation/swiftui/view/onpencildoubletap(perform:))

Adds an action to perform after the user double-taps their Apple Pencil.

[`func onPencilSqueeze(perform: (PencilSqueezeGesturePhase) -> Void) -> some View`](https://developer.apple.com/documentation/swiftui/view/onpencilsqueeze(perform:))

Adds an action to perform when the user squeezes their Apple Pencil.

[`var preferredPencilDoubleTapAction: PencilPreferredAction`](https://developer.apple.com/documentation/swiftui/environmentvalues/preferredpencildoubletapaction)

The action that the user prefers to perform after double-tapping their Apple Pencil, as selected in the Settings app.

[`var preferredPencilSqueezeAction: PencilPreferredAction`](https://developer.apple.com/documentation/swiftui/environmentvalues/preferredpencilsqueezeaction)

The action that the user prefers to perform when squeezing their Apple Pencil, as selected in the Settings app.

[`struct PencilPreferredAction`](https://developer.apple.com/documentation/swiftui/pencilpreferredaction)

An action that the user prefers to perform after double-tapping their Apple Pencil.

[`struct PencilDoubleTapGestureValue`](https://developer.apple.com/documentation/swiftui/pencildoubletapgesturevalue)

Describes the value of an Apple Pencil double-tap gesture.

[`struct PencilSqueezeGestureValue`](https://developer.apple.com/documentation/swiftui/pencilsqueezegesturevalue)

Describes the value of an Apple Pencil squeeze gesture.

[`enum PencilSqueezeGesturePhase`](https://developer.apple.com/documentation/swiftui/pencilsqueezegesturephase)

Describes the phase and value of an Apple Pencil squeeze gesture.

[`struct PencilHoverPose`](https://developer.apple.com/documentation/swiftui/pencilhoverpose)

A value describing the location and distance of an Apple Pencil hovering in the area above a view’s bounds.

### [Combining gestures](https://developer.apple.com/documentation/swiftui/gestures\#Combining-gestures)

[Composing SwiftUI gestures](https://developer.apple.com/documentation/swiftui/composing-swiftui-gestures)

Combine gestures to create complex interactions.

[`func simultaneousGesture<T>(T, including: GestureMask) -> some View`](https://developer.apple.com/documentation/swiftui/view/simultaneousgesture(_:including:))

Attaches a gesture to the view to process simultaneously with gestures defined by the view.

[`func simultaneousGesture<T>(T, isEnabled: Bool) -> some View`](https://developer.apple.com/documentation/swiftui/view/simultaneousgesture(_:isenabled:))

Attaches a gesture to the view to process simultaneously with gestures defined by the view.

[`func simultaneousGesture<T>(T, name: String, isEnabled: Bool) -> some View`](https://developer.apple.com/documentation/swiftui/view/simultaneousgesture(_:name:isenabled:))

Attaches a gesture to the view to process simultaneously with gestures defined by the view.

[`struct SequenceGesture`](https://developer.apple.com/documentation/swiftui/sequencegesture)

A gesture that’s a sequence of two gestures.

[`struct SimultaneousGesture`](https://developer.apple.com/documentation/swiftui/simultaneousgesture)

A gesture containing two gestures that can happen at the same time with neither of them preceding the other.

[`struct ExclusiveGesture`](https://developer.apple.com/documentation/swiftui/exclusivegesture)

A gesture that consists of two gestures where only one of them can succeed.

### [Defining custom gestures](https://developer.apple.com/documentation/swiftui/gestures\#Defining-custom-gestures)

[`func highPriorityGesture<T>(T, including: GestureMask) -> some View`](https://developer.apple.com/documentation/swiftui/view/highprioritygesture(_:including:))

Attaches a gesture to the view with a higher precedence than gestures defined by the view.

[`func highPriorityGesture<T>(T, isEnabled: Bool) -> some View`](https://developer.apple.com/documentation/swiftui/view/highprioritygesture(_:isenabled:))

Attaches a gesture to the view with a higher precedence than gestures defined by the view.

[`func highPriorityGesture<T>(T, name: String, isEnabled: Bool) -> some View`](https://developer.apple.com/documentation/swiftui/view/highprioritygesture(_:name:isenabled:))

Attaches a gesture to the view with a higher precedence than gestures defined by the view.

[`func handGestureShortcut(HandGestureShortcut, isEnabled: Bool) -> some View`](https://developer.apple.com/documentation/swiftui/view/handgestureshortcut(_:isenabled:))

Assigns a hand gesture shortcut to the modified control.

[`func defersSystemGestures(on: Edge.Set) -> some View`](https://developer.apple.com/documentation/swiftui/view/deferssystemgestures(on:))

Sets the screen edge from which you want your gesture to take precedence over the system gesture.

[`protocol Gesture`](https://developer.apple.com/documentation/swiftui/gesture)

An instance that matches a sequence of events to a gesture, and returns a stream of values for each of its states.

[`struct AnyGesture`](https://developer.apple.com/documentation/swiftui/anygesture)

A type-erased gesture.

[`struct HandActivationBehavior`](https://developer.apple.com/documentation/swiftui/handactivationbehavior)

An activation behavior specific to hand-driven input.

[`struct HandGestureShortcut`](https://developer.apple.com/documentation/swiftui/handgestureshortcut)

Hand gesture shortcuts describe finger and wrist movements that the user can perform in order to activate a button or toggle.

### [Managing gesture state](https://developer.apple.com/documentation/swiftui/gestures\#Managing-gesture-state)

[`struct GestureState`](https://developer.apple.com/documentation/swiftui/gesturestate)

A property wrapper type that updates a property while the user performs a gesture and resets the property back to its initial state when the gesture ends.

[`struct GestureStateGesture`](https://developer.apple.com/documentation/swiftui/gesturestategesture)

A gesture that updates the state provided by a gesture’s updating callback.

### [Handling activation events](https://developer.apple.com/documentation/swiftui/gestures\#Handling-activation-events)

[`func allowsWindowActivationEvents(Bool?) -> some View`](https://developer.apple.com/documentation/swiftui/view/allowswindowactivationevents(_:))

Configures whether gestures in this view hierarchy can handle events that activate the containing window.

### [Deprecated gestures](https://developer.apple.com/documentation/swiftui/gestures\#Deprecated-gestures)

[`struct MagnificationGesture`](https://developer.apple.com/documentation/swiftui/magnificationgesture)

A gesture that recognizes a magnification motion and tracks the amount of magnification.

Deprecated

[`struct RotationGesture`](https://developer.apple.com/documentation/swiftui/rotationgesture)

A gesture that recognizes a rotation motion and tracks the angle of the rotation.

Deprecated

## [See Also](https://developer.apple.com/documentation/swiftui/gestures\#see-also)

### [Event handling](https://developer.apple.com/documentation/swiftui/gestures\#Event-handling)

[API Reference\\
Input events](https://developer.apple.com/documentation/swiftui/input-events)

Respond to input from a hardware device, like a keyboard or a Touch Bar.

[API Reference\\
Clipboard](https://developer.apple.com/documentation/swiftui/clipboard)

Enable people to move or duplicate items by issuing Copy and Paste commands.

[API Reference\\
Drag and drop](https://developer.apple.com/documentation/swiftui/drag-and-drop)

Enable people to move or duplicate items by dragging them from one location to another.

[API Reference\\
Focus](https://developer.apple.com/documentation/swiftui/focus)

Identify and control which visible object responds to user interaction.

[API Reference\\
System events](https://developer.apple.com/documentation/swiftui/system-events)

React to system events, like opening a URL.

Current page is Gestures

## Menu Bar Extra
[Skip Navigation](https://developer.apple.com/documentation/swiftui/menubarextra#app-main)

- [SwiftUI](https://developer.apple.com/documentation/swiftui)
- MenuBarExtra

Structure

# MenuBarExtra

A scene that renders itself as a persistent control in the system menu bar.

macOS 13.0+

```
struct MenuBarExtra<Label, Content> where Label : View, Content : View
```

## [Overview](https://developer.apple.com/documentation/swiftui/menubarextra\#overview)

Use a `MenuBarExtra` when you want to provide access to commonly used functionality, even when your app is not active.

```

```

Or alternatively, to create a utility app that only shows in the menu bar.

```

```

An app that only shows in the menu bar will be automatically terminated if the user removes the extra from the menu bar.

For apps that only show in the menu bar, a common behavior is for the app to not display its icon in either the Dock or the application switcher. To enable this behavior, set the [`LSUIElement`](https://developer.apple.com/documentation/BundleResources/Information-Property-List/LSUIElement) flag in your app’s [`Information Property List`](https://developer.apple.com/documentation/BundleResources/Information-Property-List) file to `true`.

For more complex or data rich menu bar extras, you can use the [`window`](https://developer.apple.com/documentation/swiftui/menubarextrastyle/window) style, which displays a popover-like window from the menu bar icon that contains standard controls. You define the layout and contents of those controls with the content that you provide:

```

```

## [Topics](https://developer.apple.com/documentation/swiftui/menubarextra\#topics)

### [Creating a menu bar extra](https://developer.apple.com/documentation/swiftui/menubarextra\#Creating-a-menu-bar-extra)

[`init(_:content:)`](https://developer.apple.com/documentation/swiftui/menubarextra/init(_:content:))

Creates a menu bar extra with a key for a localized string to use as the label. The extra defines the primary scene of an `App`.

[`init(content: () -> Content, label: () -> Label)`](https://developer.apple.com/documentation/swiftui/menubarextra/init(content:label:))

Creates a menu bar extra that will be displayed in the system menu bar, and defines the primary scene of an `App`.

[`init(_:isInserted:content:)`](https://developer.apple.com/documentation/swiftui/menubarextra/init(_:isinserted:content:))

Creates a menu bar extra with a key for a localized string to use as the label. The item will be displayed in the system menu bar when the specified binding is set to `true`. If the user removes the item from the menu bar, the binding will be set to `false`.

[`init(isInserted: Binding<Bool>, content: () -> Content, label: () -> Label)`](https://developer.apple.com/documentation/swiftui/menubarextra/init(isinserted:content:label:))

Creates a menu bar extra. The item will be displayed in the system menu bar when the specified binding is set to `true`. If the user removes the item from the menu bar, the binding will be set to `false`.

### [Creating a menu bar extra with an image](https://developer.apple.com/documentation/swiftui/menubarextra\#Creating-a-menu-bar-extra-with-an-image)

[`init(_:image:content:)`](https://developer.apple.com/documentation/swiftui/menubarextra/init(_:image:content:))

Creates a menu bar extra with an image to use as the items label. The provided title will be used by the accessibility system.

[`init(_:image:isInserted:content:)`](https://developer.apple.com/documentation/swiftui/menubarextra/init(_:image:isinserted:content:))

Creates a menu bar extra with an image to use as the items label. The provided title will be used by the accessibility system.

[`init(_:systemImage:content:)`](https://developer.apple.com/documentation/swiftui/menubarextra/init(_:systemimage:content:))

Creates a menu bar extra with a system image to use as the items label. The provided title will be used by the accessibility system.

[`init(_:systemImage:isInserted:content:)`](https://developer.apple.com/documentation/swiftui/menubarextra/init(_:systemimage:isinserted:content:))

Creates a menu bar extra with a system image to use as the items label. The provided title will be used by the accessibility system.

## [Relationships](https://developer.apple.com/documentation/swiftui/menubarextra\#relationships)

### [Conforms To](https://developer.apple.com/documentation/swiftui/menubarextra\#conforms-to)

- [`Scene`](https://developer.apple.com/documentation/swiftui/scene)

## [See Also](https://developer.apple.com/documentation/swiftui/menubarextra\#see-also)

### [Creating a menu bar extra](https://developer.apple.com/documentation/swiftui/menubarextra\#Creating-a-menu-bar-extra)

[`func menuBarExtraStyle<S>(S) -> some Scene`](https://developer.apple.com/documentation/swiftui/scene/menubarextrastyle(_:))

Sets the style for menu bar extra created by this scene.

[`protocol MenuBarExtraStyle`](https://developer.apple.com/documentation/swiftui/menubarextrastyle)

A specification for the appearance and behavior of a menu bar extra scene.

Current page is MenuBarExtra

## SwiftUI App Delegate Integration
[Skip Navigation](https://developer.apple.com/documentation/swiftui/uiapplicationdelegateadaptor#app-main)

## ImmersionChangeContext Overview
[Skip Navigation](https://developer.apple.com/documentation/swiftui/immersionchangecontext#app-main)

- [SwiftUI](https://developer.apple.com/documentation/swiftui)
- ImmersionChangeContext

Structure

# ImmersionChangeContext

A structure that represents a state of immersion of your app.

macOS 26.0+BetavisionOS 2.0+

```
struct ImmersionChangeContext
```

## [Overview](https://developer.apple.com/documentation/swiftui/immersionchangecontext\#overview)

You don’t use this structure directly. Instead, SwiftUI provides instances of this structure via the `onImmersionChange` modifier’s closure.

## [Topics](https://developer.apple.com/documentation/swiftui/immersionchangecontext\#topics)

### [Instance Properties](https://developer.apple.com/documentation/swiftui/immersionchangecontext\#Instance-Properties)

[`let amount: Double?`](https://developer.apple.com/documentation/swiftui/immersionchangecontext/amount)

The current amount of immersion.

## [Relationships](https://developer.apple.com/documentation/swiftui/immersionchangecontext\#relationships)

### [Conforms To](https://developer.apple.com/documentation/swiftui/immersionchangecontext\#conforms-to)

- [`Sendable`](https://developer.apple.com/documentation/Swift/Sendable)
- [`SendableMetatype`](https://developer.apple.com/documentation/Swift/SendableMetatype)

## [See Also](https://developer.apple.com/documentation/swiftui/immersionchangecontext\#see-also)

### [Responding to immersion changes](https://developer.apple.com/documentation/swiftui/immersionchangecontext\#Responding-to-immersion-changes)

[`func onImmersionChange(initial: Bool, (ImmersionChangeContext, ImmersionChangeContext) -> Void) -> some View`](https://developer.apple.com/documentation/swiftui/view/onimmersionchange(initial:_:))

Performs an action when the immersion state of your app changes.

Beta Software

This documentation contains preliminary information about an API or technology in development. This information is subject to change, and software implemented according to this documentation should be tested with final operating system software.

[Learn more about using Apple's beta software](https://developer.apple.com/support/beta-software/)

Current page is ImmersionChangeContext

## SwiftUI Accessible Appearance
[Skip Navigation](https://developer.apple.com/documentation/swiftui/accessible-appearance#app-main)

## Open Settings Action
[Skip Navigation](https://developer.apple.com/documentation/swiftui/opensettingsaction#app-main)

## SwiftUI Glass Effect
[Skip Navigation](https://developer.apple.com/documentation/swiftui/glassbackgroundeffect#app-main)

## SwiftUI System Events
[Skip Navigation](https://developer.apple.com/documentation/swiftui/system-events#app-main)

## SwiftUI Modal Presentations
[Skip Navigation](https://developer.apple.com/documentation/swiftui/modal-presentations#app-main)

Collection

- [SwiftUI](https://developer.apple.com/documentation/swiftui)
- Modal presentations

API Collection

# Modal presentations

Present content in a separate view that offers focused interaction.

## [Overview](https://developer.apple.com/documentation/swiftui/modal-presentations\#Overview)

To draw attention to an important, narrowly scoped task, you display a modal presentation, like an alert, popover, sheet, or confirmation dialog.

![](https://docs-assets.developer.apple.com/published/669dc3d73261bcf3bda09c163d0c4f64/modal-presentations-hero%402x.png)

In SwiftUI, you create a modal presentation using a view modifier that defines how the presentation looks and the condition under which SwiftUI presents it. SwiftUI detects when the condition changes and makes the presentation for you. Because you provide a [`Binding`](https://developer.apple.com/documentation/swiftui/binding) to the condition that initiates the presentation, SwiftUI can reset the underlying value when the user dismisses the presentation.

For design guidance, see [Modality](https://developer.apple.com/design/Human-Interface-Guidelines/modality) in the Human Interface Guidelines.

## [Topics](https://developer.apple.com/documentation/swiftui/modal-presentations\#topics)

### [Configuring a dialog](https://developer.apple.com/documentation/swiftui/modal-presentations\#Configuring-a-dialog)

[`struct DialogSeverity`](https://developer.apple.com/documentation/swiftui/dialogseverity)

The severity of an alert or confirmation dialog.

### [Showing a sheet, cover, or popover](https://developer.apple.com/documentation/swiftui/modal-presentations\#Showing-a-sheet-cover-or-popover)

[`func sheet<Content>(isPresented: Binding<Bool>, onDismiss: (() -> Void)?, content: () -> Content) -> some View`](https://developer.apple.com/documentation/swiftui/view/sheet(ispresented:ondismiss:content:))

Presents a sheet when a binding to a Boolean value that you provide is true.

[`func sheet<Item, Content>(item: Binding<Item?>, onDismiss: (() -> Void)?, content: (Item) -> Content) -> some View`](https://developer.apple.com/documentation/swiftui/view/sheet(item:ondismiss:content:))

Presents a sheet using the given item as a data source for the sheet’s content.

[`func fullScreenCover<Content>(isPresented: Binding<Bool>, onDismiss: (() -> Void)?, content: () -> Content) -> some View`](https://developer.apple.com/documentation/swiftui/view/fullscreencover(ispresented:ondismiss:content:))

Presents a modal view that covers as much of the screen as possible when binding to a Boolean value you provide is true.

[`func fullScreenCover<Item, Content>(item: Binding<Item?>, onDismiss: (() -> Void)?, content: (Item) -> Content) -> some View`](https://developer.apple.com/documentation/swiftui/view/fullscreencover(item:ondismiss:content:))

Presents a modal view that covers as much of the screen as possible using the binding you provide as a data source for the sheet’s content.

[`func popover<Item, Content>(item: Binding<Item?>, attachmentAnchor: PopoverAttachmentAnchor, arrowEdge: Edge?, content: (Item) -> Content) -> some View`](https://developer.apple.com/documentation/swiftui/view/popover(item:attachmentanchor:arrowedge:content:))

Presents a popover using the given item as a data source for the popover’s content.

[`func popover<Content>(isPresented: Binding<Bool>, attachmentAnchor: PopoverAttachmentAnchor, arrowEdge: Edge?, content: () -> Content) -> some View`](https://developer.apple.com/documentation/swiftui/view/popover(ispresented:attachmentanchor:arrowedge:content:))

Presents a popover when a given condition is true.

[`enum PopoverAttachmentAnchor`](https://developer.apple.com/documentation/swiftui/popoverattachmentanchor)

An attachment anchor for a popover.

### [Adapting a presentation size](https://developer.apple.com/documentation/swiftui/modal-presentations\#Adapting-a-presentation-size)

[`func presentationCompactAdaptation(horizontal: PresentationAdaptation, vertical: PresentationAdaptation) -> some View`](https://developer.apple.com/documentation/swiftui/view/presentationcompactadaptation(horizontal:vertical:))

Specifies how to adapt a presentation to horizontally and vertically compact size classes.

[`func presentationCompactAdaptation(PresentationAdaptation) -> some View`](https://developer.apple.com/documentation/swiftui/view/presentationcompactadaptation(_:))

Specifies how to adapt a presentation to compact size classes.

[`struct PresentationAdaptation`](https://developer.apple.com/documentation/swiftui/presentationadaptation)

Strategies for adapting a presentation to a different size class.

[`func presentationSizing(some PresentationSizing) -> some View`](https://developer.apple.com/documentation/swiftui/view/presentationsizing(_:))

Sets the sizing of the containing presentation.

[`protocol PresentationSizing`](https://developer.apple.com/documentation/swiftui/presentationsizing)

A type that defines the size of the presentation content and how the presentation size adjusts to its content’s size changing.

[`struct PresentationSizingRoot`](https://developer.apple.com/documentation/swiftui/presentationsizingroot)

A proxy to a view provided to the presentation with a defined presentation size.

[`struct PresentationSizingContext`](https://developer.apple.com/documentation/swiftui/presentationsizingcontext)

Contextual information about a presentation.

### [Configuring a sheet’s height](https://developer.apple.com/documentation/swiftui/modal-presentations\#Configuring-a-sheets-height)

[`func presentationDetents(Set<PresentationDetent>) -> some View`](https://developer.apple.com/documentation/swiftui/view/presentationdetents(_:))

Sets the available detents for the enclosing sheet.

[`func presentationDetents(Set<PresentationDetent>, selection: Binding<PresentationDetent>) -> some View`](https://developer.apple.com/documentation/swiftui/view/presentationdetents(_:selection:))

Sets the available detents for the enclosing sheet, giving you programmatic control of the currently selected detent.

[`func presentationContentInteraction(PresentationContentInteraction) -> some View`](https://developer.apple.com/documentation/swiftui/view/presentationcontentinteraction(_:))

Configures the behavior of swipe gestures on a presentation.

[`func presentationDragIndicator(Visibility) -> some View`](https://developer.apple.com/documentation/swiftui/view/presentationdragindicator(_:))

Sets the visibility of the drag indicator on top of a sheet.

[`struct PresentationDetent`](https://developer.apple.com/documentation/swiftui/presentationdetent)

A type that represents a height where a sheet naturally rests.

[`protocol CustomPresentationDetent`](https://developer.apple.com/documentation/swiftui/custompresentationdetent)

The definition of a custom detent with a calculated height.

[`struct PresentationContentInteraction`](https://developer.apple.com/documentation/swiftui/presentationcontentinteraction)

A behavior that you can use to influence how a presentation responds to swipe gestures.

### [Styling a sheet and its background](https://developer.apple.com/documentation/swiftui/modal-presentations\#Styling-a-sheet-and-its-background)

[`func presentationCornerRadius(CGFloat?) -> some View`](https://developer.apple.com/documentation/swiftui/view/presentationcornerradius(_:))

Requests that the presentation have a specific corner radius.

[`func presentationBackground<S>(S) -> some View`](https://developer.apple.com/documentation/swiftui/view/presentationbackground(_:))

Sets the presentation background of the enclosing sheet using a shape style.

[`func presentationBackground<V>(alignment: Alignment, content: () -> V) -> some View`](https://developer.apple.com/documentation/swiftui/view/presentationbackground(alignment:content:))

Sets the presentation background of the enclosing sheet to a custom view.

[`func presentationBackgroundInteraction(PresentationBackgroundInteraction) -> some View`](https://developer.apple.com/documentation/swiftui/view/presentationbackgroundinteraction(_:))

Controls whether people can interact with the view behind a presentation.

[`struct PresentationBackgroundInteraction`](https://developer.apple.com/documentation/swiftui/presentationbackgroundinteraction)

The kinds of interaction available to views behind a presentation.

### [Presenting an alert](https://developer.apple.com/documentation/swiftui/modal-presentations\#Presenting-an-alert)

[`struct AlertScene`](https://developer.apple.com/documentation/swiftui/alertscene)

A scene that renders itself as a standalone alert dialog.

[`func alert(_:isPresented:actions:)`](https://developer.apple.com/documentation/swiftui/view/alert(_:ispresented:actions:))

Presents an alert when a given condition is true, using a text view for the title.

[`func alert(_:isPresented:presenting:actions:)`](https://developer.apple.com/documentation/swiftui/view/alert(_:ispresented:presenting:actions:))

Presents an alert using the given data to produce the alert’s content and a text view as a title.

[`func alert<E, A>(isPresented: Binding<Bool>, error: E?, actions: () -> A) -> some View`](https://developer.apple.com/documentation/swiftui/view/alert(ispresented:error:actions:))

Presents an alert when an error is present.

[`func alert(_:isPresented:actions:message:)`](https://developer.apple.com/documentation/swiftui/view/alert(_:ispresented:actions:message:))

Presents an alert with a message when a given condition is true using a text view as a title.

[`func alert(_:isPresented:presenting:actions:message:)`](https://developer.apple.com/documentation/swiftui/view/alert(_:ispresented:presenting:actions:message:))

Presents an alert with a message using the given data to produce the alert’s content and a text view for a title.

[`func alert<E, A, M>(isPresented: Binding<Bool>, error: E?, actions: (E) -> A, message: (E) -> M) -> some View`](https://developer.apple.com/documentation/swiftui/view/alert(ispresented:error:actions:message:))

Presents an alert with a message when an error is present.

### [Getting confirmation for an action](https://developer.apple.com/documentation/swiftui/modal-presentations\#Getting-confirmation-for-an-action)

[`func confirmationDialog(_:isPresented:titleVisibility:actions:)`](https://developer.apple.com/documentation/swiftui/view/confirmationdialog(_:ispresented:titlevisibility:actions:))

Presents a confirmation dialog when a given condition is true, using a text view for the title.

[`func confirmationDialog(_:isPresented:titleVisibility:presenting:actions:)`](https://developer.apple.com/documentation/swiftui/view/confirmationdialog(_:ispresented:titlevisibility:presenting:actions:))

Presents a confirmation dialog using data to produce the dialog’s content and a text view for the title.

[`func dismissalConfirmationDialog(_:shouldPresent:actions:)`](https://developer.apple.com/documentation/swiftui/view/dismissalconfirmationdialog(_:shouldpresent:actions:))

Presents a confirmation dialog when a dismiss action has been triggered.

### [Showing a confirmation dialog with a message](https://developer.apple.com/documentation/swiftui/modal-presentations\#Showing-a-confirmation-dialog-with-a-message)

[`func confirmationDialog(_:isPresented:titleVisibility:actions:message:)`](https://developer.apple.com/documentation/swiftui/view/confirmationdialog(_:ispresented:titlevisibility:actions:message:))

Presents a confirmation dialog with a message when a given condition is true, using a text view for the title.

[`func confirmationDialog(_:isPresented:titleVisibility:presenting:actions:message:)`](https://developer.apple.com/documentation/swiftui/view/confirmationdialog(_:ispresented:titlevisibility:presenting:actions:message:))

Presents a confirmation dialog with a message using data to produce the dialog’s content and a text view for the message.

[`func dismissalConfirmationDialog(_:shouldPresent:actions:message:)`](https://developer.apple.com/documentation/swiftui/view/dismissalconfirmationdialog(_:shouldpresent:actions:message:))

Presents a confirmation dialog when a dismiss action has been triggered.

### [Configuring a dialog](https://developer.apple.com/documentation/swiftui/modal-presentations\#Configuring-a-dialog)

[`func dialogIcon(Image?) -> some View`](https://developer.apple.com/documentation/swiftui/view/dialogicon(_:))

Configures the icon used by dialogs within this view.

[`func dialogIcon(Image?) -> some Scene`](https://developer.apple.com/documentation/swiftui/scene/dialogicon(_:))

Configures the icon used by alerts.

[`func dialogSeverity(DialogSeverity) -> some View`](https://developer.apple.com/documentation/swiftui/view/dialogseverity(_:))

[`func dialogSeverity(DialogSeverity) -> some Scene`](https://developer.apple.com/documentation/swiftui/scene/dialogseverity(_:))

Sets the severity for alerts.

[`func dialogSuppressionToggle(isSuppressed: Binding<Bool>) -> some View`](https://developer.apple.com/documentation/swiftui/view/dialogsuppressiontoggle(issuppressed:))

Enables user suppression of dialogs and alerts presented within `self`, with a default suppression message on macOS. Unused on other platforms.

[`func dialogSuppressionToggle(isSuppressed: Binding<Bool>) -> some Scene`](https://developer.apple.com/documentation/swiftui/scene/dialogsuppressiontoggle(issuppressed:))

Enables user suppression of an alert with a custom suppression message.

[`func dialogSuppressionToggle(_:isSuppressed:)`](https://developer.apple.com/documentation/swiftui/view/dialogsuppressiontoggle(_:issuppressed:))

Enables user suppression of dialogs and alerts presented within `self`, with a custom suppression message on macOS. Unused on other platforms.

### [Exporting to file](https://developer.apple.com/documentation/swiftui/modal-presentations\#Exporting-to-file)

[`func fileExporter(isPresented:document:contentType:defaultFilename:onCompletion:)`](https://developer.apple.com/documentation/swiftui/view/fileexporter(ispresented:document:contenttype:defaultfilename:oncompletion:))

Presents a system interface for exporting a document that’s stored in a value type, like a structure, to a file on disk.

[`func fileExporter(isPresented:documents:contentType:onCompletion:)`](https://developer.apple.com/documentation/swiftui/view/fileexporter(ispresented:documents:contenttype:oncompletion:))

Presents a system interface for exporting a collection of value type documents to files on disk.

[`func fileExporter(isPresented:document:contentTypes:defaultFilename:onCompletion:onCancellation:)`](https://developer.apple.com/documentation/swiftui/view/fileexporter(ispresented:document:contenttypes:defaultfilename:oncompletion:oncancellation:))

Presents a system interface for allowing the user to export a `FileDocument` to a file on disk.

[`func fileExporter(isPresented:documents:contentTypes:onCompletion:onCancellation:)`](https://developer.apple.com/documentation/swiftui/view/fileexporter(ispresented:documents:contenttypes:oncompletion:oncancellation:))

Presents a system dialog for allowing the user to export a collection of documents that conform to `FileDocument` to files on disk.

[`func fileExporter<T>(isPresented: Binding<Bool>, item: T?, contentTypes: [UTType], defaultFilename: String?, onCompletion: (Result<URL, any Error>) -> Void, onCancellation: () -> Void) -> some View`](https://developer.apple.com/documentation/swiftui/view/fileexporter(ispresented:item:contenttypes:defaultfilename:oncompletion:oncancellation:))

Presents a system interface allowing the user to export a `Transferable` item to file on disk.

[`func fileExporter<C, T>(isPresented: Binding<Bool>, items: C, contentTypes: [UTType], onCompletion: (Result<[URL], any Error>) -> Void, onCancellation: () -> Void) -> some View`](https://developer.apple.com/documentation/swiftui/view/fileexporter(ispresented:items:contenttypes:oncompletion:oncancellation:))

Presents a system interface allowing the user to export a collection of items to files on disk.

[`func fileExporterFilenameLabel(_:)`](https://developer.apple.com/documentation/swiftui/view/fileexporterfilenamelabel(_:))

On macOS, configures the `fileExporter` with a label for the file name field.

### [Importing from file](https://developer.apple.com/documentation/swiftui/modal-presentations\#Importing-from-file)

[`func fileImporter(isPresented: Binding<Bool>, allowedContentTypes: [UTType], allowsMultipleSelection: Bool, onCompletion: (Result<[URL], any Error>) -> Void) -> some View`](https://developer.apple.com/documentation/swiftui/view/fileimporter(ispresented:allowedcontenttypes:allowsmultipleselection:oncompletion:))

Presents a system interface for allowing the user to import multiple files.

[`func fileImporter(isPresented: Binding<Bool>, allowedContentTypes: [UTType], onCompletion: (Result<URL, any Error>) -> Void) -> some View`](https://developer.apple.com/documentation/swiftui/view/fileimporter(ispresented:allowedcontenttypes:oncompletion:))

Presents a system interface for allowing the user to import an existing file.

[`func fileImporter(isPresented: Binding<Bool>, allowedContentTypes: [UTType], allowsMultipleSelection: Bool, onCompletion: (Result<[URL], any Error>) -> Void, onCancellation: () -> Void) -> some View`](https://developer.apple.com/documentation/swiftui/view/fileimporter(ispresented:allowedcontenttypes:allowsmultipleselection:oncompletion:oncancellation:))

Presents a system dialog for allowing the user to import multiple files.

### [Moving a file](https://developer.apple.com/documentation/swiftui/modal-presentations\#Moving-a-file)

[`func fileMover(isPresented: Binding<Bool>, file: URL?, onCompletion: (Result<URL, any Error>) -> Void) -> some View`](https://developer.apple.com/documentation/swiftui/view/filemover(ispresented:file:oncompletion:))

Presents a system interface for allowing the user to move an existing file to a new location.

[`func fileMover<C>(isPresented: Binding<Bool>, files: C, onCompletion: (Result<[URL], any Error>) -> Void) -> some View`](https://developer.apple.com/documentation/swiftui/view/filemover(ispresented:files:oncompletion:))

Presents a system interface for allowing the user to move a collection of existing files to a new location.

[`func fileMover(isPresented: Binding<Bool>, file: URL?, onCompletion: (Result<URL, any Error>) -> Void, onCancellation: () -> Void) -> some View`](https://developer.apple.com/documentation/swiftui/view/filemover(ispresented:file:oncompletion:oncancellation:))

Presents a system dialog for allowing the user to move an existing file to a new location.

[`func fileMover<C>(isPresented: Binding<Bool>, files: C, onCompletion: (Result<[URL], any Error>) -> Void, onCancellation: () -> Void) -> some View`](https://developer.apple.com/documentation/swiftui/view/filemover(ispresented:files:oncompletion:oncancellation:))

Presents a system dialog for allowing the user to move a collection of existing files to a new location.

### [Configuring a file dialog](https://developer.apple.com/documentation/swiftui/modal-presentations\#Configuring-a-file-dialog)

[`func fileDialogBrowserOptions(FileDialogBrowserOptions) -> some View`](https://developer.apple.com/documentation/swiftui/view/filedialogbrowseroptions(_:))

On macOS, configures the `fileExporter`, `fileImporter`, or `fileMover` to provide a refined URL search experience: include or exclude hidden files, allow searching by tag, etc.

[`func fileDialogConfirmationLabel(_:)`](https://developer.apple.com/documentation/swiftui/view/filedialogconfirmationlabel(_:))

On macOS, configures the the `fileExporter`, `fileImporter`, or `fileMover` with a custom confirmation button label.

[`func fileDialogCustomizationID(String) -> some View`](https://developer.apple.com/documentation/swiftui/view/filedialogcustomizationid(_:))

On macOS, configures the `fileExporter`, `fileImporter`, or `fileMover` to persist and restore the file dialog configuration.

[`func fileDialogDefaultDirectory(URL?) -> some View`](https://developer.apple.com/documentation/swiftui/view/filedialogdefaultdirectory(_:))

Configures the `fileExporter`, `fileImporter`, or `fileMover` to open with the specified default directory.

[`func fileDialogImportsUnresolvedAliases(Bool) -> some View`](https://developer.apple.com/documentation/swiftui/view/filedialogimportsunresolvedaliases(_:))

On macOS, configures the `fileExporter`, `fileImporter`, or `fileMover` behavior when a user chooses an alias.

[`func fileDialogMessage(_:)`](https://developer.apple.com/documentation/swiftui/view/filedialogmessage(_:))

On macOS, configures the the `fileExporter`, `fileImporter`, or `fileMover` with a custom text that is presented to the user, similar to a title.

[`func fileDialogURLEnabled(Predicate<URL>) -> some View`](https://developer.apple.com/documentation/swiftui/view/filedialogurlenabled(_:))

On macOS, configures the the `fileImporter` or `fileMover` to conditionally disable presented URLs.

[`struct FileDialogBrowserOptions`](https://developer.apple.com/documentation/swiftui/filedialogbrowseroptions)

The way that file dialogs present the file system.

### [Presenting an inspector](https://developer.apple.com/documentation/swiftui/modal-presentations\#Presenting-an-inspector)

[`func inspector<V>(isPresented: Binding<Bool>, content: () -> V) -> some View`](https://developer.apple.com/documentation/swiftui/view/inspector(ispresented:content:))

Inserts an inspector at the applied position in the view hierarchy.

[`func inspectorColumnWidth(CGFloat) -> some View`](https://developer.apple.com/documentation/swiftui/view/inspectorcolumnwidth(_:))

Sets a fixed, preferred width for the inspector containing this view when presented as a trailing column.

[`func inspectorColumnWidth(min: CGFloat?, ideal: CGFloat, max: CGFloat?) -> some View`](https://developer.apple.com/documentation/swiftui/view/inspectorcolumnwidth(min:ideal:max:))

Sets a flexible, preferred width for the inspector in a trailing-column presentation.

### [Dismissing a presentation](https://developer.apple.com/documentation/swiftui/modal-presentations\#Dismissing-a-presentation)

[`var isPresented: Bool`](https://developer.apple.com/documentation/swiftui/environmentvalues/ispresented)

A Boolean value that indicates whether the view associated with this environment is currently presented.

[`var dismiss: DismissAction`](https://developer.apple.com/documentation/swiftui/environmentvalues/dismiss)

An action that dismisses the current presentation.

[`struct DismissAction`](https://developer.apple.com/documentation/swiftui/dismissaction)

An action that dismisses a presentation.

[`func interactiveDismissDisabled(Bool) -> some View`](https://developer.apple.com/documentation/swiftui/view/interactivedismissdisabled(_:))

Conditionally prevents interactive dismissal of presentations like popovers, sheets, and inspectors.

### [Deprecated modal presentations](https://developer.apple.com/documentation/swiftui/modal-presentations\#Deprecated-modal-presentations)

[`struct Alert`](https://developer.apple.com/documentation/swiftui/alert)

A representation of an alert presentation.

Deprecated

[`struct ActionSheet`](https://developer.apple.com/documentation/swiftui/actionsheet)

A representation of an action sheet presentation.

Deprecated

## [See Also](https://developer.apple.com/documentation/swiftui/modal-presentations\#see-also)

### [App structure](https://developer.apple.com/documentation/swiftui/modal-presentations\#App-structure)

[API Reference\\
App organization](https://developer.apple.com/documentation/swiftui/app-organization)

Define the entry point and top-level structure of your app.

[API Reference\\
Scenes](https://developer.apple.com/documentation/swiftui/scenes)

Declare the user interface groupings that make up the parts of your app.

[API Reference\\
Windows](https://developer.apple.com/documentation/swiftui/windows)

Display user interface content in a window or a collection of windows.

[API Reference\\
Immersive spaces](https://developer.apple.com/documentation/swiftui/immersive-spaces)

Display unbounded content in a person’s surroundings.

[API Reference\\
Documents](https://developer.apple.com/documentation/swiftui/documents)

Enable people to open and manage documents.

[API Reference\\
Navigation](https://developer.apple.com/documentation/swiftui/navigation)

Enable people to move between different parts of your app’s view hierarchy within a scene.

[API Reference\\
Toolbars](https://developer.apple.com/documentation/swiftui/toolbars)

Provide immediate access to frequently used commands and controls.

[API Reference\\
Search](https://developer.apple.com/documentation/swiftui/search)

Enable people to search for text or other content within your app.

[API Reference\\
App extensions](https://developer.apple.com/documentation/swiftui/app-extensions)

Extend your app’s basic functionality to other parts of the system, like by adding a Widget.

Current page is Modal presentations

## Automatic Glass Effect
[Skip Navigation](https://developer.apple.com/documentation/swiftui/automaticglassbackgroundeffect#app-main)

## SwiftUI Lists Overview
[Skip Navigation](https://developer.apple.com/documentation/swiftui/lists#app-main)

## SwiftUI Persistent Storage
[Skip Navigation](https://developer.apple.com/documentation/swiftui/persistent-storage#app-main)

## SwiftUI WindowGroup Guide
[Skip Navigation](https://developer.apple.com/documentation/swiftui/windowgroup#app-main)

## SwiftUI Scene Overview
[Skip Navigation](https://developer.apple.com/documentation/swiftui/scene#app-main)

## SwiftUI ScrollTargetBehavior
[Skip Navigation](https://developer.apple.com/documentation/swiftui/scrolltargetbehaviorpropertiescontext#app-main)

## SwiftUI Content Toolbar
[Skip Navigation](https://developer.apple.com/documentation/swiftui/contenttoolbarplacement#app-main)

## SwiftUI Input Events
[Skip Navigation](https://developer.apple.com/documentation/swiftui/input-events#app-main)

## SwiftUI SettingsLink Guide
[Skip Navigation](https://developer.apple.com/documentation/swiftui/settingslink#app-main)

## Immersive Space Displacement
[Skip Navigation](https://developer.apple.com/documentation/swiftui/environmentvalues/immersivespacedisplacement#app-main)

## Window Styles in macOS
[Skip Navigation](https://developer.apple.com/documentation/swiftui/customizing-window-styles-and-state-restoration-behavior-in-macos#app-main)

## ScenePhase in SwiftUI
[Skip Navigation](https://developer.apple.com/documentation/swiftui/scenephase#app-main)

## SwiftUI Immersive Spaces
[Skip Navigation](https://developer.apple.com/documentation/swiftui/immersive-spaces#app-main)

## SwiftUI Drawing Guide
[Skip Navigation](https://developer.apple.com/documentation/swiftui/drawing-and-graphics#app-main)

## SwiftUI Menu Bar Styles
[Skip Navigation](https://developer.apple.com/documentation/swiftui/menubarextrastyle#app-main)

## UIKit and SwiftUI Integration
[Skip Navigation](https://developer.apple.com/documentation/swiftui/uikit-integration#app-main)

Collection

- [SwiftUI](https://developer.apple.com/documentation/swiftui)
- UIKit integration

API Collection

# UIKit integration

Add UIKit views to your SwiftUI app, or use SwiftUI views in your UIKit app.

## [Overview](https://developer.apple.com/documentation/swiftui/uikit-integration\#Overview)

Integrate SwiftUI with your app’s existing content using hosting controllers to add SwiftUI views into UIKit interfaces. A hosting controller wraps a set of SwiftUI views in a form that you can then add to your storyboard-based app.

![](https://docs-assets.developer.apple.com/published/74ee52cce15bcc5332715296b5d568d9/uikit-integration-hero%402x.png)

You can also add UIKit views and view controllers to your SwiftUI interfaces. A representable object wraps the designated view or view controller, and facilitates communication between the wrapped object and your SwiftUI views.

For design guidance, see the following sections in the Human Interface Guidelines:

- [Designing for iOS](https://developer.apple.com/design/Human-Interface-Guidelines/designing-for-ios)

- [Designing for iPadOS](https://developer.apple.com/design/Human-Interface-Guidelines/designing-for-ipados)

- [Designing for tvOS](https://developer.apple.com/design/Human-Interface-Guidelines/designing-for-tvos)


## [Topics](https://developer.apple.com/documentation/swiftui/uikit-integration\#topics)

### [Displaying SwiftUI views in UIKit](https://developer.apple.com/documentation/swiftui/uikit-integration\#Displaying-SwiftUI-views-in-UIKit)

[Using SwiftUI with UIKit](https://developer.apple.com/documentation/UIKit/using-swiftui-with-uikit)

Learn how to incorporate SwiftUI views into a UIKit app.

[Unifying your app’s animations](https://developer.apple.com/documentation/swiftui/unifying-your-app-s-animations)

Create a consistent UI animation experience across SwiftUI, UIKit, and AppKit.

[`class UIHostingController`](https://developer.apple.com/documentation/swiftui/uihostingcontroller)

A UIKit view controller that manages a SwiftUI view hierarchy.

[`struct UIHostingControllerSizingOptions`](https://developer.apple.com/documentation/swiftui/uihostingcontrollersizingoptions)

Options for how a hosting controller tracks its content’s size.

[`struct UIHostingConfiguration`](https://developer.apple.com/documentation/swiftui/uihostingconfiguration)

A content configuration suitable for hosting a hierarchy of SwiftUI views.

[`protocol UIHostingSceneDelegate`](https://developer.apple.com/documentation/swiftui/uihostingscenedelegate)

Extends `UIKit/UISceneDelegate` to bridge SwiftUI scenes.

Beta

### [Adding UIKit views to SwiftUI view hierarchies](https://developer.apple.com/documentation/swiftui/uikit-integration\#Adding-UIKit-views-to-SwiftUI-view-hierarchies)

[`protocol UIViewRepresentable`](https://developer.apple.com/documentation/swiftui/uiviewrepresentable)

A wrapper for a UIKit view that you use to integrate that view into your SwiftUI view hierarchy.

[`struct UIViewRepresentableContext`](https://developer.apple.com/documentation/swiftui/uiviewrepresentablecontext)

Contextual information about the state of the system that you use to create and update your UIKit view.

[`protocol UIViewControllerRepresentable`](https://developer.apple.com/documentation/swiftui/uiviewcontrollerrepresentable)

A view that represents a UIKit view controller.

[`struct UIViewControllerRepresentableContext`](https://developer.apple.com/documentation/swiftui/uiviewcontrollerrepresentablecontext)

Contextual information about the state of the system that you use to create and update your UIKit view controller.

### [Adding UIKit gesture recognizers into SwiftUI view hierarchies](https://developer.apple.com/documentation/swiftui/uikit-integration\#Adding-UIKit-gesture-recognizers-into-SwiftUI-view-hierarchies)

[`protocol UIGestureRecognizerRepresentable`](https://developer.apple.com/documentation/swiftui/uigesturerecognizerrepresentable)

A wrapper for a `UIGestureRecognizer` that you use to integrate that gesture recognizer into your SwiftUI hierarchy.

[`struct UIGestureRecognizerRepresentableContext`](https://developer.apple.com/documentation/swiftui/uigesturerecognizerrepresentablecontext)

Contextual information about the state of the system that you use to create and update a represented gesture recognizer.

[`struct UIGestureRecognizerRepresentableCoordinateSpaceConverter`](https://developer.apple.com/documentation/swiftui/uigesturerecognizerrepresentablecoordinatespaceconverter)

A proxy structure used to convert locations to/from coordinate spaces in the hierarchy of the SwiftUI view associated with a [`UIGestureRecognizerRepresentable`](https://developer.apple.com/documentation/swiftui/uigesturerecognizerrepresentable).

### [Sharing configuration information](https://developer.apple.com/documentation/swiftui/uikit-integration\#Sharing-configuration-information)

[`typealias UITraitBridgedEnvironmentKey`](https://developer.apple.com/documentation/swiftui/uitraitbridgedenvironmentkey)

### [Hosting an ornament in UIKit](https://developer.apple.com/documentation/swiftui/uikit-integration\#Hosting-an-ornament-in-UIKit)

[`class UIHostingOrnament`](https://developer.apple.com/documentation/swiftui/uihostingornament)

A model that represents an ornament suitable for being hosted in UIKit.

[`class UIOrnament`](https://developer.apple.com/documentation/swiftui/uiornament)

The abstract base class that represents an ornament.

## [See Also](https://developer.apple.com/documentation/swiftui/uikit-integration\#see-also)

### [Framework integration](https://developer.apple.com/documentation/swiftui/uikit-integration\#Framework-integration)

[API Reference\\
AppKit integration](https://developer.apple.com/documentation/swiftui/appkit-integration)

Add AppKit views to your SwiftUI app, or use SwiftUI views in your AppKit app.

[API Reference\\
WatchKit integration](https://developer.apple.com/documentation/swiftui/watchkit-integration)

Add WatchKit views to your SwiftUI app, or use SwiftUI views in your WatchKit app.

[API Reference\\
Technology-specific views](https://developer.apple.com/documentation/swiftui/technology-specific-views)

Use SwiftUI views that other Apple frameworks provide.

Current page is UIKit integration

## SwiftUI App Settings
[Skip Navigation](https://developer.apple.com/documentation/swiftui/settings#app-main)

## SwiftUI Preferences Guide
[Skip Navigation](https://developer.apple.com/documentation/swiftui/preferences#app-main)

## SwiftUI Menus and Commands
[Skip Navigation](https://developer.apple.com/documentation/swiftui/menus-and-commands#app-main)

## SwiftUI App Development
[Skip Navigation](https://developer.apple.com/documentation/swiftui/app#app-main)

## WatchKit and SwiftUI Integration
[Skip Navigation](https://developer.apple.com/documentation/swiftui/watchkit-integration#app-main)

## SwiftUI View Fundamentals
[Skip Navigation](https://developer.apple.com/documentation/swiftui/view-fundamentals#app-main)

## SwiftUI Scroll Views
[Skip Navigation](https://developer.apple.com/documentation/swiftui/scroll-views#app-main)

## SwiftUI Menu Bar Style
[Skip Navigation](https://developer.apple.com/documentation/swiftui/scene/menubarextrastyle(_:)#app-main)

## SwiftUI Immersive Space
[Skip Navigation](https://developer.apple.com/documentation/swiftui/immersivespace#app-main)

## SwiftUI Multiplatform App
[Skip Navigation](https://developer.apple.com/documentation/swiftui/food_truck_building_a_swiftui_multiplatform_app#app-main)

## Accessible Navigation in SwiftUI
[Skip Navigation](https://developer.apple.com/documentation/swiftui/accessible-navigation#app-main)

## SwiftUI Drag and Drop
[Skip Navigation](https://developer.apple.com/documentation/swiftui/drag-and-drop#app-main)

## SwiftUI Layout Basics
[Skip Navigation](https://developer.apple.com/documentation/swiftui/layout-fundamentals#app-main)

## Immersive Space Actions
[Skip Navigation](https://developer.apple.com/documentation/swiftui/openimmersivespaceaction#app-main)

## Xcode Previews for SwiftUI
[Skip Navigation](https://developer.apple.com/documentation/swiftui/previews-in-xcode#app-main)

## SwiftUI Shapes Guide
[Skip Navigation](https://developer.apple.com/documentation/swiftui/shapes#app-main)

## SwiftUI ImmersionStyle Guide
[Skip Navigation](https://developer.apple.com/documentation/swiftui/scene/immersionstyle(selection:in:)#app-main)

## Accessible Controls in SwiftUI
[Skip Navigation](https://developer.apple.com/documentation/swiftui/accessible-controls#app-main)

## Upper Limb Visibility
[Skip Navigation](https://developer.apple.com/documentation/swiftui/view/upperlimbvisibility(_:)#app-main)

## SwiftUI Scene Builder
[Skip Navigation](https://developer.apple.com/documentation/swiftui/scenebuilder#app-main)

## SwiftUI Glass Background
[Skip Navigation](https://developer.apple.com/documentation/swiftui/glassbackgroundeffectconfiguration#app-main)

## SwiftUI Animations Guide
[Skip Navigation](https://developer.apple.com/documentation/swiftui/animations#app-main)

## SwiftUI Environment Values
[Skip Navigation](https://developer.apple.com/documentation/swiftui/environment-values#app-main)

## SwiftUI View Configuration
[Skip Navigation](https://developer.apple.com/documentation/swiftui/view-configuration#app-main)

## Immersive Environment Picker
[Skip Navigation](https://developer.apple.com/documentation/swiftui/view/immersiveenvironmentpicker(content:)#app-main)

## Dismiss Immersive Space
[Skip Navigation](https://developer.apple.com/documentation/swiftui/dismissimmersivespaceaction#app-main)

## Model Data in SwiftUI
[Skip Navigation](https://developer.apple.com/documentation/swiftui/model-data#app-main)

## Immersive Content Brightness
[Skip Navigation](https://developer.apple.com/documentation/swiftui/immersivecontentbrightness#app-main)

## SwiftUI Layout Adjustments
[Skip Navigation](https://developer.apple.com/documentation/swiftui/layout-adjustments#app-main)

## SwiftUI Window Management
[Skip Navigation](https://developer.apple.com/documentation/swiftui/window#app-main)

- [SwiftUI](https://developer.apple.com/documentation/swiftui)
- Window

Structure

# Window

A scene that presents its content in a single, unique window.

macOS 13.0+visionOS 26.0+Beta

```
struct Window<Content> where Content : View
```

## [Overview](https://developer.apple.com/documentation/swiftui/window\#overview)

Use a `Window` scene to augment the main interface of your app with a window that gives people access to supplemental functionality. For example, you can create a secondary window in a mail reader app that enables people to view the status of their account connections:

```

```

Provide a title as the first argument to the window’s intializer. The system uses the title to identify the window to people using your app in the window’s title bar or in the list of available singleton windows that the Windows menu displays automatically.

### [Open a window programmatically](https://developer.apple.com/documentation/swiftui/window\#Open-a-window-programmatically)

People open the window by selecting it in the Windows menu, but you can also open the window programmatically using the [`openWindow`](https://developer.apple.com/documentation/swiftui/environmentvalues/openwindow) action that you read from the environment. Use the `id` parameter that you initialize the window with to indicate which window to open. For example, you can create a button to open the window from the previous example:

```

```

If the window is already open when you call this action, the action brings the open window to the front. Be sure to use unique identifiers across all of the `Window` and [`WindowGroup`](https://developer.apple.com/documentation/swiftui/windowgroup) instances that you define.

### [Dismiss a window programmatically](https://developer.apple.com/documentation/swiftui/window\#Dismiss-a-window-programmatically)

The system provides people with controls to close windows, but you can also close a window programmatically using the [`dismiss`](https://developer.apple.com/documentation/swiftui/environmentvalues/dismiss) action from within the window’s view hierarchy. For example, you can include a button in the connection doctor view that dismisses the view:

```

```

The dismiss action doesn’t close the window if you call it from a modal — like a sheet or a popover — that you present from within the window. In that case, the action dismisses the modal presentation instead.

### [Use a window as the main scene](https://developer.apple.com/documentation/swiftui/window\#Use-a-window-as-the-main-scene)

You can use a window as the main scene of your app when multi-window functionality isn’t appropriate. For example, it might not make sense to display more than one window for a video call app that relies on a hardware resource, like a camera:

```

```

If your app uses a single window as its primary scene, the app quits when the window closes. This behavior differs from an app that uses a [`WindowGroup`](https://developer.apple.com/documentation/swiftui/windowgroup) as its primary scene, where the app continues to run even after closing all of its windows.

## [Topics](https://developer.apple.com/documentation/swiftui/window\#topics)

### [Creating a window](https://developer.apple.com/documentation/swiftui/window\#Creating-a-window)

[`init(_:id:content:)`](https://developer.apple.com/documentation/swiftui/window/init(_:id:content:))

Creates a window with a title and an identifier.

## [Relationships](https://developer.apple.com/documentation/swiftui/window\#relationships)

### [Conforms To](https://developer.apple.com/documentation/swiftui/window\#conforms-to)

- [`Scene`](https://developer.apple.com/documentation/swiftui/scene)

## [See Also](https://developer.apple.com/documentation/swiftui/window\#see-also)

### [Creating windows](https://developer.apple.com/documentation/swiftui/window\#Creating-windows)

[`struct WindowGroup`](https://developer.apple.com/documentation/swiftui/windowgroup)

A scene that presents a group of identically structured windows.

[`struct UtilityWindow`](https://developer.apple.com/documentation/swiftui/utilitywindow)

A specialized window scene that provides secondary utility to the content of the main scenes of an application.

[`protocol WindowStyle`](https://developer.apple.com/documentation/swiftui/windowstyle)

A specification for the appearance and interaction of a window.

[`func windowStyle<S>(S) -> some Scene`](https://developer.apple.com/documentation/swiftui/scene/windowstyle(_:))

Sets the style for windows created by this scene.

Beta Software

This documentation contains preliminary information about an API or technology in development. This information is subject to change, and software implemented according to this documentation should be tested with final operating system software.

[Learn more about using Apple's beta software](https://developer.apple.com/support/beta-software/)

Current page is Window

## Xcode Library Customization
[Skip Navigation](https://developer.apple.com/documentation/swiftui/xcode-library-customization#app-main)

## Multiple Windows in SwiftUI
[Skip Navigation](https://developer.apple.com/documentation/swiftui/bringing_multiple_windows_to_your_swiftui_app#app-main)

## SwiftUI Immersion Change
[Skip Navigation](https://developer.apple.com/documentation/swiftui/view/onimmersionchange(initial:_:)#app-main)

## Immersive Content Brightness
[Skip Navigation](https://developer.apple.com/documentation/swiftui/scene/immersivecontentbrightness(_:)#app-main)

## Upper Limb Visibility
[Skip Navigation](https://developer.apple.com/documentation/swiftui/scene/upperlimbvisibility(_:)#app-main)

## SwiftUI Life Cycle Migration
[Skip Navigation](https://developer.apple.com/documentation/swiftui/migrating-to-the-swiftui-life-cycle#app-main)

## Feathered Glass Effect
[Skip Navigation](https://developer.apple.com/documentation/swiftui/featheredglassbackgroundeffect#app-main)

## SwiftUI Tables Guide
[Skip Navigation](https://developer.apple.com/documentation/swiftui/tables#app-main)

## SwiftUI and AppKit Integration
[Skip Navigation](https://developer.apple.com/documentation/swiftui/appkit-integration#app-main)

## SwiftUI Focus Management
[Skip Navigation](https://developer.apple.com/documentation/swiftui/focus#app-main)

## SwiftUI View Groupings
[Skip Navigation](https://developer.apple.com/documentation/swiftui/view-groupings#app-main)

## SwiftUI App Organization
[Skip Navigation](https://developer.apple.com/documentation/swiftui/app-organization#app-main)

## SwiftUI Windows Overview
[Skip Navigation](https://developer.apple.com/documentation/swiftui/windows#app-main)

## SwiftUI Immersive Space
[Skip Navigation](https://developer.apple.com/documentation/swiftui/immersivespacecontentbuilder#app-main)

