import SwiftUI
import UIKit

struct TimelinePanel: View {
    @ObservedObject var model: EditorModel
    @State private var zoom = 35.0
    @State private var snapping = true
    @State private var follow = true
    @State private var waves: [UUID: [Float]] = [:]
    @State private var startRequest = 0
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                Button {
                    model.stop()
                    model.seek(0)
                    startRequest &+= 1
                } label: {
                    Image(systemName: "backward.end.fill").frame(width: 36, height: 32)
                }
                .foregroundStyle(DesignTokens.amber)
                .accessibilityLabel(L("Revenir au début"))
                .accessibilityIdentifier("timelineStart")
                Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
                Slider(value: $zoom, in: 12...160).accessibilityLabel(L("Zoom temporel"))
                Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary)
                Button { snapping.toggle() } label: { Image(systemName: "point.topleft.down.to.point.bottomright.curvepath").frame(width: 44, height: 32).foregroundStyle(snapping ? DesignTokens.amber : .secondary) }.accessibilityLabel(L("Aimantation")).accessibilityValue(snapping ? "On" : "Off")
                Button { follow.toggle() } label: { Image(systemName: follow ? "location.fill" : "location").frame(width: 36, height: 32) }.accessibilityLabel(L("Suivre la lecture"))
            }.font(.caption).padding(.horizontal, 18)
            TimelineCanvas(model: model, zoom: $zoom, snapping: snapping, follow: follow, waves: waves, startRequest: startRequest)
                .frame(minHeight: 40)
                .task(id: model.document.assets.count) {
                    for asset in model.document.assets where asset.kind == .audio || asset.kind == .video {
                        if waves[asset.id] == nil, let wave = try? await MediaImporter.shared.waveform(asset: asset, rootURL: model.rootURL, sampleCount: 180) { waves[asset.id] = wave }
                    }
                }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in waves.removeAll() }
    }
}
struct TimelineCanvas: UIViewRepresentable {
    @ObservedObject var model: EditorModel
    @Binding var zoom: Double
    var snapping: Bool
    var follow: Bool
    var waves: [UUID: [Float]]
    var startRequest: Int
    func makeUIView(context: Context) -> TimelineScrollView { let view = TimelineScrollView(); view.model = model; view.zoomChanged = { zoom = $0 }; return view }
    func updateUIView(_ view: TimelineScrollView, context: Context) {
        view.model = model; view.pointsPerSecond = zoom; view.snapping = snapping; view.waves = waves
        view.canvas.plan = model.plan; view.canvas.selectedID = model.selectedClipID; view.canvas.playhead = model.playhead; view.canvas.thumbnails = model.thumbnails; view.canvas.waves = waves
        view.refresh(follow: follow && model.playing)
        view.showStart(request: startRequest)
    }
}
final class TimelineScrollView: UIScrollView, UIScrollViewDelegate, UIGestureRecognizerDelegate, UIContextMenuInteractionDelegate {
    var model: EditorModel?
    var pointsPerSecond = 35.0
    var snapping = true
    var waves: [UUID: [Float]] = [:]
    var zoomChanged: ((Double) -> Void)?
    let canvas = TimelineDrawingView()
    private var gestureOrigin: Clip?
    private var gestureClip: RenderClip?
    private var scrubMode = false
    private var trimEdge: Bool?
    private var initialX = 0.0
    private var initialZoom = 35.0
    private var pinchAnchor = 0.0
    private var initialOffset = 0.0
    private var pan: UIPanGestureRecognizer!
    private var moveLongPress: UILongPressGestureRecognizer!
    private var moveMode = false
    private var lastLocation: CGPoint = .zero
    private var autoScrollLink: CADisplayLink?
    private var handledStartRequest = 0
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.06, green: 0.075, blue: 0.1, alpha: 1)
        showsHorizontalScrollIndicator = true; showsVerticalScrollIndicator = true
        alwaysBounceHorizontal = true; alwaysBounceVertical = true; isDirectionalLockEnabled = true; delegate = self
        accessibilityIdentifier = "timelineScroll"
        addSubview(canvas)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped)); canvas.addGestureRecognizer(tap)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched)); addGestureRecognizer(pinch)
        pan = UIPanGestureRecognizer(target: self, action: #selector(trimmed)); pan.delegate = self; canvas.addGestureRecognizer(pan)
        panGestureRecognizer.require(toFail: pan)
        moveLongPress = UILongPressGestureRecognizer(target: self, action: #selector(moved)); moveLongPress.minimumPressDuration = 0.45; moveLongPress.delegate = self; canvas.addGestureRecognizer(moveLongPress)
        canvas.addInteraction(UIContextMenuInteraction(delegate: self))
        canvas.isUserInteractionEnabled = true
        isAccessibilityElement = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func refresh(follow: Bool) {
        canvas.pointsPerSecond = pointsPerSecond
        canvas.beatMarkers = model?.document.rhythmMarkers ?? []
        let width = max(bounds.width, (canvas.plan?.duration.seconds ?? 0) * pointsPerSecond + 90)
        contentSize = CGSize(width: width, height: max(bounds.height, 53 + Double(canvas.trackKeys.count) * 43))
        canvas.frame = CGRect(origin: contentOffset, size: bounds.size)
        if follow {
            let x = 54 + canvas.playhead * pointsPerSecond
            if x - contentOffset.x > bounds.width * 0.8 || x < contentOffset.x + 54 { contentOffset.x = max(0, min(contentSize.width - bounds.width, x - bounds.width * 0.3)) }
        }
        canvas.visibleRect = CGRect(origin: contentOffset, size: bounds.size)
        canvas.setNeedsDisplay()
        updateAccessibility()
    }
    override func layoutSubviews() { super.layoutSubviews(); refresh(follow: false) }
    func showStart(request: Int) {
        guard request != handledStartRequest else { return }
        handledStartRequest = request
        setContentOffset(CGPoint(x: 0, y: contentOffset.y), animated: true)
    }
    func scrollViewDidScroll(_ scrollView: UIScrollView) { canvas.frame = CGRect(origin: contentOffset, size: bounds.size); canvas.visibleRect = CGRect(origin: contentOffset, size: bounds.size); canvas.setNeedsDisplay() }
    private func canvasPoint(_ gesture: UIGestureRecognizer) -> CGPoint { let p = gesture.location(in: canvas); return CGPoint(x: p.x + contentOffset.x, y: p.y + contentOffset.y) }
    private func hit(_ point: CGPoint) -> RenderClip? { canvas.plan?.clips.reversed().first { canvas.rect(for: $0).insetBy(dx: -8, dy: -3).contains(point) } }
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == moveLongPress {
            // Captions reserve the long press for their deletion menu. Other media keep
            // the existing long-press drag gesture.
            return hit(canvasPoint(gestureRecognizer))?.clip.isCaption != true
        }
        guard gestureRecognizer == pan else { return true }
        let p = canvasPoint(gestureRecognizer)
        let velocity = pan.velocity(in: self)
        guard abs(velocity.x) >= abs(velocity.y) else { return false }
        if p.y < 44 { return true }
        guard let c = hit(p), c.id == model?.selectedClipID else { return false }
        return true
    }
    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        let point = canvasPoint(gesture)
        if let clip = hit(point) { model?.selectClip(clip) }
        else { model?.seek(max(0, (point.x - 54) / pointsPerSecond)) }
    }
    @objc private func pinched(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began: initialZoom = pointsPerSecond; pinchAnchor = max(0, (canvasPoint(gesture).x - 54) / pointsPerSecond); initialOffset = gesture.location(in: self).x - contentOffset.x
        case .changed:
            let value = min(160, max(12, initialZoom * gesture.scale)); pointsPerSecond = value; zoomChanged?(value); refresh(follow: false)
            contentOffset.x = max(0, min(contentSize.width - bounds.width, pinchAnchor * value + 54 - initialOffset))
        default: break
        }
    }
    @objc private func trimmed(_ gesture: UIPanGestureRecognizer) {
        guard let model else { return }
        let point = canvasPoint(gesture); lastLocation = point
        switch gesture.state {
        case .began:
            if point.y < 44 { scrubMode = true; model.seek(max(0, (point.x-54)/pointsPerSecond)); return }
            guard let c = hit(point) else { return }
            gestureOrigin = c.clip; gestureClip = c; initialX = point.x
            let r = canvas.rect(for: c)
            let leadingDistance = abs(point.x-r.minX), trailingDistance = abs(point.x-r.maxX)
            let edgeWidth = min(14.0, max(6.0, r.width * 0.18))
            if r.width >= 28, min(leadingDistance, trailingDistance) <= edgeWidth {
                trimEdge = leadingDistance <= trailingDistance
                moveMode = false
                model.beginGesture(L("Précision temporelle"))
            } else {
                trimEdge = nil
                moveMode = true
                model.beginGesture(L("Déplacer le segment"))
            }
            startAutoscroll()
        case .changed:
            if scrubMode { model.seek(max(0, (point.x-54)/pointsPerSecond)) }
            else if moveMode { applyMove(at: point.x) }
            else { applyTrim(at: point.x) }
        case .ended: if !scrubMode { model.endGesture() }; resetGesture()
        case .cancelled, .failed: if !scrubMode { model.endGesture() }; resetGesture()
        default: break
        }
    }
    private func applyTrim(at x: Double) {
        guard let model, let origin = gestureOrigin, let rc = gestureClip, let leading = trimEdge else { return }
        var delta = (x - initialX) / pointsPerSecond
        let boundary = leading ? rc.globalStart.seconds : rc.end.seconds
        if snapping { delta = snapped(boundary + delta, ignoring: origin.id) - boundary }
        // Trimming a handle only removes source; use the timing inspector to extend.
        let cut = min(max(0, leading ? delta : -delta), max(0, origin.duration.seconds - 1 / 30))
        model.updateGesture { d in
            d.updateClip(origin.id) { $0 = origin }
            try DocumentEditor.trimClip(origin.id, from: .init(seconds: leading ? cut : 0), to: .init(seconds: leading ? origin.duration.seconds : origin.duration.seconds - cut), in: &d)
        }
    }
    private func applyMove(at x: Double) {
        guard let model, let origin = gestureOrigin, let rc = gestureClip else { return }
        let global = max(0, rc.globalStart.seconds + (x-initialX)/pointsPerSecond)
        let target = snapping ? snapped(global, ignoring: rc.id) : global
        let base = rc.globalStart.seconds - origin.start.seconds
        model.updateGesture { document in
            let local = max(0, target-base)
            document.updateClip(origin.id) { $0.start = .init(seconds: local) }
            if let index = document.scenes.firstIndex(where: { $0.id == rc.sceneID }) {
                document.scenes[index].duration = max(document.scenes[index].duration, .init(seconds: local) + origin.duration)
            }
        }
    }
    @objc private func moved(_ gesture: UILongPressGestureRecognizer) {
        guard let model else { return }; let point = canvasPoint(gesture); lastLocation = point
        switch gesture.state {
        case .began:
            guard let c = hit(point) else { return }; gestureOrigin = c.clip; gestureClip = c; initialX = point.x; model.selectedClipID = c.id; model.selectedSceneID = c.sceneID
            moveMode = true; model.beginGesture(L("Déplacer le segment")); startAutoscroll()
        case .changed:
            applyMove(at: point.x)
        case .ended, .cancelled, .failed: if gestureOrigin != nil { model.endGesture() }; resetGesture()
        default: break
        }
    }
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        let point = CGPoint(x: location.x + contentOffset.x, y: location.y + contentOffset.y)
        guard let caption = hit(point), caption.clip.isCaption else { return nil }
        model?.selectedClipID = caption.id
        model?.selectedSceneID = caption.sceneID
        return UIContextMenuConfiguration(identifier: caption.id as NSUUID, previewProvider: nil) { [weak self] _ in
            let deleteSegment = UIAction(
                title: L("Supprimer ce segment"),
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { [weak self] _ in self?.model?.deleteClip(caption.id) }
            let deleteTrack = UIAction(
                title: L("Supprimer toute la piste"),
                image: UIImage(systemName: "captions.bubble"),
                attributes: .destructive
            ) { [weak self] _ in self?.confirmCaptionTrackDeletion() }
            return UIMenu(title: caption.clip.text, children: [deleteSegment, deleteTrack])
        }
    }
    private func confirmCaptionTrackDeletion() {
        guard let controller = presentingViewController() else { return }
        let alert = UIAlertController(title: L("Supprimer la piste de sous-titres ?"), message: L("Tous les sous-titres du montage seront supprimés. Vous pourrez annuler cette action."), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L("Annuler"), style: .cancel))
        alert.addAction(UIAlertAction(title: L("Supprimer toute la piste"), style: .destructive) { [weak self] _ in self?.model?.deleteCaptionTrack() })
        controller.present(alert, animated: true)
    }
    private func presentingViewController() -> UIViewController? {
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }
    private func snapped(_ value: Double, ignoring: UUID) -> Double {
        guard let plan = canvas.plan else { return value }
        let targets: [Double] = plan.scenes.flatMap { [$0.start.seconds, $0.end.seconds] } + plan.clips.filter { $0.id != ignoring }.flatMap { [$0.globalStart.seconds, $0.end.seconds] } + [0.0, canvas.playhead] + canvas.beatMarkers.map { $0.time.seconds }
        return targets.min(by: { abs($0-value) < abs($1-value) }).flatMap { abs($0-value) < 8/pointsPerSecond ? $0 : nil } ?? value
    }
    private func startAutoscroll() { autoScrollLink?.invalidate(); let link = CADisplayLink(target: self, selector: #selector(autoscroll)); link.add(to: .main, forMode: .common); autoScrollLink = link }
    @objc private func autoscroll() {
        let screen = lastLocation.x-contentOffset.x
        let delta: Double = screen < 25 ? -3 : screen > bounds.width-25 ? 3 : 0
        guard delta != 0 else { return }
        let old = contentOffset.x; contentOffset.x = max(0, min(contentSize.width - bounds.width, old + delta)); lastLocation.x += contentOffset.x-old
        if moveMode { applyMove(at: lastLocation.x) }
        else if trimEdge != nil { applyTrim(at: lastLocation.x) }
    }
    private func resetGesture() { scrubMode = false; moveMode = false; gestureOrigin = nil; gestureClip = nil; trimEdge = nil; autoScrollLink?.invalidate(); autoScrollLink = nil }
    override func didMoveToWindow() { super.didMoveToWindow(); if window == nil { autoScrollLink?.invalidate(); autoScrollLink = nil } }
    private func updateAccessibility() {
        guard let plan = canvas.plan else { return }
        accessibilityElements = plan.clips.filter { canvas.rect(for: $0).intersects(canvas.visibleRect) }.map { clip in
            let element = TimelineAccessibility(container: self)
            element.accessibilityLabel = "\(clip.clip.text.isEmpty ? clip.clip.kind.rawValue : clip.clip.text), \(String(format: "%.2f", clip.globalStart.seconds)), \(String(format: "%.2f", clip.duration.seconds)) s"
            element.accessibilityTraits = clip.id == model?.selectedClipID ? [.button, .selected] : .button
            element.accessibilityFrameInContainerSpace = canvas.rect(for: clip).offsetBy(dx: -contentOffset.x, dy: -contentOffset.y)
            element.activate = { [weak self] in self?.model?.selectClip(clip) }
            if clip.clip.isCaption {
                element.accessibilityIdentifier = "captionSegment-\(clip.id.uuidString)"
                element.accessibilityCustomActions = [
                    UIAccessibilityCustomAction(name: L("Supprimer ce segment")) { [weak self] _ in self?.model?.deleteClip(clip.id); return true },
                    UIAccessibilityCustomAction(name: L("Supprimer toute la piste")) { [weak self] _ in self?.confirmCaptionTrackDeletion(); return true }
                ]
            }
            return element
        }
    }
}
final class TimelineAccessibility: UIAccessibilityElement {
    var activate: (() -> Void)?
    convenience init(container: Any) { self.init(accessibilityContainer: container) }
    override func accessibilityActivate() -> Bool { activate?(); return true }
}
final class TimelineDrawingView: UIView {
    var plan: RenderPlan?
    var beatMarkers: [BeatMarker] = []
    var selectedID: UUID?
    var pointsPerSecond = 35.0
    var playhead = 0.0
    var thumbnails: [UUID: CGImage] = [:]
    var waves: [UUID: [Float]] = [:]
    var visibleRect = CGRect.zero
        override init(frame: CGRect) { super.init(frame: frame); backgroundColor = .clear; isOpaque = false }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func trackKey(_ rc: RenderClip) -> String { let c = rc.clip; let group = c.kind == .audio ? "3" : c.kind == .text ? "2" : c.layer > 0 ? "1" : "0"; return group + String(format: "%05d", c.layer+1000) + (c.kind == .audio && rc.sceneID == nil ? "G" : "S") }
    var trackKeys: [String] { Array(Set(plan?.clips.map { trackKey($0) } ?? [])).sorted() }
    func lane(_ clip: RenderClip) -> Int { trackKeys.firstIndex(of: trackKey(clip)) ?? 0 }
    func colorIndex(_ clip: Clip) -> Int { clip.kind == .audio ? 3 : clip.kind == .text ? 2 : clip.layer > 0 ? 1 : 0 }
    func rect(for clip: RenderClip) -> CGRect { CGRect(x: 54 + clip.globalStart.seconds * pointsPerSecond, y: 47 + Double(lane(clip)) * 43, width: max(4, clip.duration.seconds * pointsPerSecond - 2), height: 36) }
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), let plan else { return }
        context.translateBy(x: -visibleRect.minX, y: -visibleRect.minY)
        let visible = visibleRect.insetBy(dx: -10, dy: 0)
        let caption: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedSystemFont(ofSize: 9, weight: .medium), .foregroundColor: UIColor(white: 0.6, alpha: 1)]
        let step = pointsPerSecond < 20 ? 5.0 : pointsPerSecond < 60 ? 2.0 : 1.0
        let first = max(0, floor((visible.minX-54)/pointsPerSecond/step)*step)
        let last = min(plan.duration.seconds, (visible.maxX-54)/pointsPerSecond)
        for marker in beatMarkers where marker.time.seconds <= plan.duration.seconds {
            let x = 54 + marker.time.seconds * pointsPerSecond
            guard x >= visible.minX, x <= visible.maxX else { continue }
            context.setFillColor(UIColor.systemTeal.cgColor)
            context.move(to: CGPoint(x: x - 4, y: 18)); context.addLine(to: CGPoint(x: x + 4, y: 18)); context.addLine(to: CGPoint(x: x, y: 24)); context.closePath(); context.fillPath()
            context.setStrokeColor(UIColor.systemTeal.withAlphaComponent(0.3).cgColor); context.setLineDash(phase: 0, lengths: [2, 3]); context.move(to: CGPoint(x: x, y: 24)); context.addLine(to: CGPoint(x: x, y: 53 + Double(trackKeys.count) * 43)); context.strokePath(); context.setLineDash(phase: 0, lengths: [])
        }
        if first <= last { for second in stride(from: first, through: last, by: step) { let x = 54 + second*pointsPerSecond; (timeLabel(second) as NSString).draw(at: CGPoint(x: x+3, y: 4), withAttributes: caption); context.setStrokeColor(UIColor.white.withAlphaComponent(0.08).cgColor); context.move(to: CGPoint(x: x,y: 21)); context.addLine(to: CGPoint(x: x,y: 220)); context.strokePath() } }
        for (index, scene) in plan.scenes.enumerated() {
            let x = 54 + scene.start.seconds*pointsPerSecond
            if x + scene.duration.seconds*pointsPerSecond < visible.minX || x > visible.maxX { continue }
            context.setFillColor(UIColor(red: 0.92, green: 0.65, blue: 0.35, alpha: 0.12).cgColor); context.fill(CGRect(x: x, y: 23, width: scene.duration.seconds*pointsPerSecond-2, height: 18))
            (String(format: "%02d", index+1) as NSString).draw(at: CGPoint(x: x+4,y: 26), withAttributes: caption)
            if scene.transition.duration > .zero { let end = x+(scene.duration-scene.transition.duration).seconds*pointsPerSecond; context.setFillColor(UIColor.systemOrange.withAlphaComponent(0.4).cgColor); context.fill(CGRect(x: end,y: 24,width: scene.transition.duration.seconds*pointsPerSecond,height: 17)) }
        }
        let colors = [UIColor(red: 0.44, green: 0.61, blue: 0.61, alpha: 1), UIColor(red: 0.51, green: 0.58, blue: 0.75, alpha: 1), UIColor(red: 0.9, green: 0.64, blue: 0.35, alpha: 1), UIColor(red: 0.55, green: 0.69, blue: 0.54, alpha: 1)]
        for rc in plan.clips {
            let r = self.rect(for: rc)
            guard r.intersects(visible) else { continue }
            let color = colors[colorIndex(rc.clip)]; color.withAlphaComponent(0.35).setFill(); UIBezierPath(roundedRect: r, cornerRadius: 5).fill()
            context.saveGState(); UIBezierPath(roundedRect: r, cornerRadius: 5).addClip()
            if rc.clip.kind == .audio, let id = rc.clip.assetID, let wave = waves[id], !wave.isEmpty {
                context.setStrokeColor(color.cgColor); context.setLineWidth(1)
                let left = max(r.minX+3, visible.minX), right = min(r.maxX-3, visible.maxX)
                if left < right { for x in stride(from: left, to: right, by: 3) {
                    let t = (x-r.minX)/r.width
                    let index = min(wave.count-1, max(0, Int(t*Double(wave.count))))
                    let height = max(1, Double(wave[index])*15)
                    context.move(to: CGPoint(x: x,y:r.midY-height)); context.addLine(to: CGPoint(x:x,y:r.midY+height))
                }; context.strokePath() }
            } else if rc.clip.kind != .text, let sceneID = rc.sceneID, let thumbnail = thumbnails[sceneID] {
                UIImage(cgImage: thumbnail).draw(in: CGRect(x: r.minX, y: r.minY, width: 30, height: 36))
            }
            let label = rc.clip.text.isEmpty ? (rc.sceneID == nil ? "⌖ " : "") + (plan.assets.first { $0.id == rc.clip.assetID }?.name ?? rc.clip.kind.rawValue) : rc.clip.text
            (label as NSString).draw(in: CGRect(x:r.minX+6, y:r.minY+11,width:r.width-12,height:16), withAttributes: [.font:UIFont.systemFont(ofSize:9, weight:.semibold),.foregroundColor:UIColor.white])
            context.restoreGState()
            if rc.id == selectedID { UIColor(red:0.92,green:0.65,blue:0.35,alpha:1).setStroke(); let p=UIBezierPath(roundedRect:r.insetBy(dx:1,dy:1),cornerRadius:5); p.lineWidth=2; p.stroke(); context.setFillColor(UIColor.white.cgColor); for x in [r.minX+4,r.maxX-6] { context.fill(CGRect(x:x,y:r.midY-7,width:2,height:14)) } }
            for key in rc.clip.keyframes where key.property == .scale { let x = r.minX+(key.time-rc.clip.animationOffset).seconds*pointsPerSecond; if r.contains(CGPoint(x:x,y:r.midY)) { context.setFillColor(UIColor.white.cgColor); context.fillEllipse(in:CGRect(x:x-2,y:r.maxY-6,width:4,height:4)) } }
        }
        let x=54+playhead*pointsPerSecond; context.setStrokeColor(UIColor.white.cgColor); context.setLineWidth(1.5); context.move(to:CGPoint(x:x,y:18)); context.addLine(to:CGPoint(x:x,y:225)); context.strokePath()
        context.setFillColor(UIColor.white.cgColor); context.fill(CGRect(x:x-4,y:16,width:8,height:5))
        // Fixed track headers and a viewport-sized canvas keep memory independent of duration.
        context.setFillColor(UIColor(red: 0.06, green: 0.075, blue: 0.1, alpha: 1).cgColor)
        context.fill(CGRect(x: visibleRect.minX, y: visibleRect.minY, width: 48, height: visibleRect.height))
        for (index,key) in trackKeys.enumerated() {
            let title = key.hasPrefix("3") ? L("Son") : key.hasPrefix("2") ? L("Texte") : key.hasPrefix("1") ? L("Calque") : L("Image")
            (title as NSString).draw(at: CGPoint(x: visibleRect.minX + 5, y: 60 + Double(index) * 43), withAttributes: caption)
        }
    }
}
