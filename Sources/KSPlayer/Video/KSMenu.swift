//
//  KSMenu.swift
//  KSPlayer
//
//  Created by Alanko5 on 15/12/2022.
//

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

extension UIMenu {
    func updateActionState(actionTitle: String? = nil) -> UIMenu {
        for action in children {
            guard let action = action as? UIAction else {
                continue
            }
            action.state = action.title == actionTitle ? .on : .off
        }
        return self
    }

    @available(tvOS 15.0, *)
    convenience init?<U>(title: String, current: U?, list: [U], addDisabled: Bool = false, titleFunc: (U) -> String, completition: @escaping (String, U?) -> Void) {
        if list.count < (addDisabled ? 1 : 2) {
            return nil
        }
        var actions = list.map { value in
            let item = UIAction(title: titleFunc(value)) { item in
                completition(item.title, value)
            }

            if let current, titleFunc(value) == titleFunc(current) {
                item.state = .on
            }
            return item
        }
        if addDisabled {
            actions.insert(UIAction(title: "Disabled") { item in
                completition(item.title, nil)
            }, at: 0)
        }

        self.init(title: title, children: actions)
    }
}

#if !os(tvOS)
extension UIButton {
    @available(iOS 14.0, *)
    func setMenu<U>(title: String, current: U?, list: [U], addDisabled: Bool = false, titleFunc: (U) -> String, completition handler: @escaping (U?) -> Void) {
        menu = UIMenu(title: title, current: current, list: list, addDisabled: addDisabled, titleFunc: titleFunc) { [weak self] title, value in
            guard let self else { return }
            handler(value)
            self.menu = self.menu?.updateActionState(actionTitle: title)
        }
    }
}
#endif

#if canImport(UIKit)

#else
public typealias UIMenu = NSMenu

public final class UIAction: NSMenuItem {
    private let handler: (UIAction) -> Void
    init(title: String, handler: @escaping (UIAction) -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(menuPressed), keyEquivalent: "")
        state = .off
        target = self
    }

    @objc private func menuPressed() {
        handler(self)
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension UIMenu {
    var children: [NSMenuItem] {
        items
    }

    convenience init(title: String, children: [UIAction]) {
        self.init(title: title)
        for item in children {
            addItem(item)
        }
    }
}
#endif

// MARK: - MenuController (Mac Catalyst / iOS menu-bar surface)
//
// Platform rationale: `UIMenuBuilder` and the application main-menu-bar
// (`UIMenuSystem`) only exist on iOS and Mac Catalyst — there is no
// UIKit menu bar on tvOS, and the macOS-native (AppKit) target uses
// `NSMenu` instead. The doc (§18.23) calls `buildSubtitleMenu` "the
// macOS/Catalyst menu-bar counterpart to IOSVideoPlayerView's in-view
// subtitle menu (§13.2)", so the guard is widened from the original
// `#if os(iOS)` to also cover Mac Catalyst.
#if os(iOS) || targetEnvironment(macCatalyst)
/// RE: 0x1014ED910 (MenuController metadata accessor, 1.3.15 —
/// `_objc_opt_self(_TtC8KSPlayer14MenuController)`). A stateless helper
/// (0 stored fields per `types.json`) that installs the app's menu-bar
/// items and rebuilds the in-view subtitle menu. Relocated here from
/// `IOSVideoPlayerView.swift` per the UIComponents cluster map, which
/// assigns `MenuController` to `KSMenu.swift`.
@MainActor
public class MenuController {
    /// Installs the player's custom menu-bar items into the host app menu.
    /// The binary removes the stock Format menu and inserts an "Open File"
    /// command at the start of the File menu.
    public init(with builder: UIMenuBuilder) {
        builder.remove(menu: .format)
        builder.insertChild(MenuController.openFileMenu(), atStartOfMenu: .file)
    }

    /// RE: 0x1014ED72C (`MenuController_buildOpenFileMenu`, 1.3.15). Builds
    /// a `.displayInline` File-menu section holding a single ⌘O key command
    /// that triggers `IOSVideoPlayerView.openFileAction(_:)`.
    ///
    /// Binary-verified details:
    /// - The key command input is "O" (`0x4f`) with `.command` modifier.
    /// - Its title is `NSLocalizedString("Open File")` (`0x6c6946206e65704f`
    ///   = "Open Fil…").
    /// - The wrapping `UIMenu` uses identifier "/" (`0x2f`) with an empty
    ///   title, `.displayInline`, and the iOS-17+ single-selection option
    ///   branch (`___isPlatformVersionAtLeast(2, 0x11, 0, 0)` →
    ///   `options = -1` i.e. `.singleSelection.rawValue` all-bits set, else
    ///   `2` i.e. `.singleSelection`).
    class func openFileMenu() -> UIMenu {
        let openCommand = UIKeyCommand(input: "O", modifierFlags: .command, action: #selector(IOSVideoPlayerView.openFileAction(_:)))
        openCommand.title = NSLocalizedString("Open File", comment: "")
        // iOS-17+ single-selection branch (matches the binary's
        // `___isPlatformVersionAtLeast(2, 0x11, 0, 0)` gate); pre-17 falls
        // back to the bare `.singleSelection` option as the binary does.
        let options: UIMenu.Options
        if #available(iOS 17.0, macCatalyst 17.0, *) {
            options = [.displayInline, .singleSelection]
        } else {
            options = [.displayInline]
        }
        return UIMenu(title: "",
                      image: nil,
                      identifier: UIMenu.Identifier("/"),
                      options: options,
                      children: [openCommand])
    }

    /// RE: 0x1014ED104 (`MenuController_buildSubtitleMenu`, 1.3.15). The
    /// macOS/Catalyst menu-bar counterpart to the in-view subtitle menu
    /// (§13.2). Verified decompile behavior, in order:
    ///
    /// 1. Walks the responder chain from `playerView` via `nextResponder`
    ///    to locate the presented `UIDocumentPickerViewController`.
    /// 2. Reads a subtitle selection stored as an associated object and
    ///    bridges it to a Bool `secondary` flag via `_swift_dynamicCast`.
    /// 3. Constructs a `URLSubtitleInfo(url:)` for the picked file.
    /// 4. Branches on `secondary`:
    ///    - primary → `KSPlayerLayer.setSelectedSubtitleInfo(info)`
    ///      (`setSelectedSubtitleInfo @ 0x1013b38c0`),
    ///    - secondary → writes `SubtitleModel.secondarySubtitleInfo`.
    /// 5. Calls `IOSVideoPlayerView.showPrompt(_:)` with a localized label
    ///    ("First Subtitle " / "Second Subtitle ") + the info's `name`
    ///    appended (binary grows the string to 0x12 / 0x19 bytes before the
    ///    `appendyySSF` of `URLSubtitleInfo.name`).
    /// 6. Builds the two parent sections via
    ///    `IOSVideoPlayerView.buildSubtitleMenuSections()` — "First Subtitle"
    ///    (`0x7553207473726946`) and "Second Subtitle"
    ///    (`0x5320646e6f636553`).
    /// 7. Assembles a `UIMenu` titled "Subtitle" (`0x656c746974627553`)
    ///    with single-selection on iOS 17+ (`options = -1` else `2`).
    /// 8. Assigns the menu to `IOSVideoPlayerView.subtitleMenuButton` via
    ///    `setMenu` / `.menu`.
    ///
    /// - Parameters:
    ///   - playerView: the player view that owns `subtitleMenuButton` and is
    ///     the responder-chain root (the binary carries this in `x20`).
    ///   - url: the subtitle file URL picked by the document picker (the
    ///     binary materializes a `Foundation.URL` value at function entry).
    class func buildSubtitleMenu(for playerView: IOSVideoPlayerView, url: URL) {
        // Step 1: walk the responder chain to find the document picker.
        // The binary stops at the first `UIDocumentPickerViewController`;
        // if none is presented there is nothing to install.
        var responder: UIResponder? = playerView
        var picker: UIDocumentPickerViewController?
        while let current = responder {
            if let found = current as? UIDocumentPickerViewController {
                picker = found
                break
            }
            responder = current.nextResponder
        }
        guard let picker else { return }

        // Step 2: read the "secondary" flag from the document picker's
        // associated object and bridge it to a Bool. A missing/incompatible
        // association reads as `false` (the binary's `local_c8 = '\0'` path).
        let secondary = (objc_getAssociatedObject(picker, &MenuController.secondarySubtitleAssociationKey) as? Bool) ?? false

        // Step 3: build the subtitle info for the picked file.
        let info = URLSubtitleInfo(url: url)

        // Step 4: route to the primary or secondary slot, and
        // Step 5: assemble the localized prompt label (+ appended name).
        let prompt: String
        if secondary {
            // Secondary path: the binary writes
            // `SubtitleModel.secondarySubtitleInfo` directly through the
            // player layer's subtitle model.
            playerView.playerLayer?.subtitleModel.secondarySubtitleInfo = info
            prompt = NSLocalizedString("Second Subtitle ", comment: "") + info.name
        } else {
            // Primary path: API-surface preservation — the binary calls the
            // discrete `KSPlayerLayer.setSelectedSubtitleInfo(_:)` entry, so
            // keep it as its own call rather than folding into the model.
            playerView.playerLayer?.setSelectedSubtitleInfo(info)
            prompt = NSLocalizedString("First Subtitle ", comment: "") + info.name
        }
        playerView.showPrompt(prompt)

        // Steps 6–8: rebuild the parent "Subtitle" menu from the
        // First/Second sections and reassign it to the subtitle button.
        let sections = playerView.buildSubtitleMenuSections()
        let menu: UIMenu
        if #available(iOS 17.0, macCatalyst 17.0, *) {
            menu = UIMenu(title: NSLocalizedString("Subtitle", comment: ""),
                          options: .singleSelection,
                          children: sections)
        } else {
            menu = UIMenu(title: NSLocalizedString("Subtitle", comment: ""),
                          children: sections)
        }
        playerView.subtitleMenuButton.menu = menu
    }

    /// Associated-object key for the document picker's "secondary subtitle"
    /// selection flag (read in `buildSubtitleMenu`). The binary stores the
    /// flag on the picker via `objc_setAssociatedObject`; this static gives
    /// a stable address to key it by.
    private static var secondarySubtitleAssociationKey: UInt8 = 0
}
#endif
