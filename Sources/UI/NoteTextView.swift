import FossifyCommons
import SwiftUI
import UIKit

/// The EditText of TextFragment: plain-text UITextView with its own undo history, the system find
/// navigator for search, optional clickable links and line wrap.
struct NoteTextView: UIViewRepresentable {
    let session: NoteSession
    let font: UIFont
    let alignment: NSTextAlignment
    let textColor: UIColor
    let tint: UIColor
    let lineWrap: Bool
    let clickableLinks: Bool
    let incognito: Bool
    let placeCursorToEnd: Bool

    func makeCoordinator() -> Coordinator { Coordinator(session: session) }

    func makeUIView(context: Context) -> UIView {
        let tv = PlainTextView(usingTextLayoutManager: false)
        tv.delegate = context.coordinator
        tv.backgroundColor = .clear
        tv.isFindInteractionEnabled = true
        tv.alwaysBounceVertical = true
        tv.keyboardDismissMode = .interactive
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        tv.smartQuotesType = .no
        tv.smartDashesType = .no
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.delegate = context.coordinator
        tap.cancelsTouchesInView = false
        tv.addGestureRecognizer(tap)
        context.coordinator.textView = tv
        session.textView = tv
        if lineWrap { return tv }
        return NoWrapContainer(textView: tv)
    }

    func updateUIView(_ view: UIView, context: Context) {
        let c = context.coordinator
        guard let tv = c.textView else { return }
        c.clickableLinks = clickableLinks
        tv.font = font
        tv.textColor = textColor
        tv.tintColor = tint
        tv.textAlignment = alignment
        tv.linkTextAttributes = [.foregroundColor: tint, .underlineStyle: NSUnderlineStyle.single.rawValue]
        let correction: UITextAutocorrectionType = incognito ? .no : .default
        if tv.autocorrectionType != correction {
            tv.autocorrectionType = correction
            tv.spellCheckingType = incognito ? .no : .default
            tv.inlinePredictionType = incognito ? .no : .default
            if tv.isFirstResponder { tv.reloadInputViews() }
        }
        if c.version != session.textVersion {
            c.version = session.textVersion
            tv.text = session.text
            tv.undoManager?.removeAllActions()
            let end = (session.text as NSString).length
            tv.selectedRange = NSRange(location: placeCursorToEnd ? end : 0, length: 0)
            c.updateUndoState()
        }
        c.linkify()
        if session.focusHandled != session.focusRequest {
            let s = session
            DispatchQueue.main.async {
                s.focusHandled = s.focusRequest
                tv.becomeFirstResponder()
            }
        }
        view.setNeedsLayout()
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        let session: NoteSession
        weak var textView: UITextView?
        var version = -1
        var clickableLinks = false
        private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

        init(session: NoteSession) {
            self.session = session
        }

        func textViewDidChange(_ textView: UITextView) {
            session.text = textView.text
            updateUndoState()
            linkify()
            textView.superview?.setNeedsLayout()
        }

        func updateUndoState() {
            session.canUndo = textView?.undoManager?.canUndo ?? false
            session.canRedo = textView?.undoManager?.canRedo ?? false
        }

        /// Linkify.WEB_URLS | EMAIL_ADDRESSES while "Make links and emails clickable" is on.
        func linkify() {
            guard let tv = textView, tv.markedTextRange == nil else { return }
            let storage = tv.textStorage
            let full = NSRange(location: 0, length: storage.length)
            var hadLinks = false
            storage.enumerateAttribute(.link, in: full) { v, _, stop in
                if v != nil { hadLinks = true; stop.pointee = true }
            }
            guard clickableLinks || hadLinks else { return }
            let selection = tv.selectedRange
            storage.beginEditing()
            storage.removeAttribute(.link, range: full)
            if clickableLinks {
                Self.detector?.enumerateMatches(in: storage.string, range: full) { m, _, _ in
                    if let m, let url = m.url { storage.addAttribute(.link, value: url, range: m.range) }
                }
            }
            storage.endEditing()
            tv.selectedRange = selection
            tv.typingAttributes = [.font: tv.font ?? UIFont.systemFont(ofSize: 17), .foregroundColor: tv.textColor ?? UIColor.label]
        }

        /// MyMovementMethod: a tap on a link opens it.
        @objc func tapped(_ g: UITapGestureRecognizer) {
            guard clickableLinks, let tv = textView else { return }
            var p = g.location(in: tv)
            p.x -= tv.textContainerInset.left
            p.y -= tv.textContainerInset.top
            let lm = tv.layoutManager
            let glyph = lm.glyphIndex(for: p, in: tv.textContainer)
            guard lm.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: tv.textContainer).contains(p) else { return }
            let index = lm.characterIndexForGlyph(at: glyph)
            guard index < tv.textStorage.length else { return }
            if let url = tv.textStorage.attribute(.link, at: index, effectiveRange: nil) as? URL {
                UIApplication.shared.open(url)
            }
        }

        nonisolated func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

/// UITextView with a private undo history per note.
final class PlainTextView: UITextView {
    private let history = UndoManager()
    override var undoManager: UndoManager? { history }

    /// enforcePlainText(): pasted rich text is inserted as plain text.
    override func paste(_ sender: Any?) {
        if let s = UIPasteboard.general.string {
            insertText(s)
        } else {
            super.paste(sender)
        }
    }
}

/// note_view_horiz_scrollable: line wrap off, scrolls both ways.
final class NoWrapContainer: UIScrollView {
    let textView: UITextView

    init(textView: UITextView) {
        self.textView = textView
        super.init(frame: .zero)
        textView.isScrollEnabled = false
        textView.textContainer.widthTracksTextView = false
        textView.textContainer.size = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        alwaysBounceVertical = true
        keyboardDismissMode = .interactive
        addSubview(textView)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let lm = textView.layoutManager
        lm.ensureLayout(for: textView.textContainer)
        let used = lm.usedRect(for: textView.textContainer)
        let inset = textView.textContainerInset
        let pad = textView.textContainer.lineFragmentPadding * 2
        let w = max(bounds.width, ceil(used.width + inset.left + inset.right + pad + 8))
        let h = max(bounds.height, ceil(used.height + inset.top + inset.bottom + 8))
        if textView.frame.size != CGSize(width: w, height: h) {
            textView.frame = CGRect(x: 0, y: 0, width: w, height: h)
            contentSize = CGSize(width: w, height: h)
        }
    }
}
