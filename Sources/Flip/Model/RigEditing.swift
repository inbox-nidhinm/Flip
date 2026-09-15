import CoreGraphics
import Foundation

// MARK: - Reading a posed frame

extension Frame {
    /// The layer as the pose leaves it.
    ///
    /// Stored geometry is always the **rest** pose — posing never writes to the
    /// artwork — so this runs at draw time and the document keeps one copy of the
    /// drawing. It also means undoing a pose is undoing a rig edit, and the
    /// artwork cannot drift out of step with the armature that drives it.
    func posed(_ layer: Layer) -> Layer { posed(layer, under: nil) }

    /// A rig carries down to everything inside the layer that holds it.
    ///
    /// This is what makes a group behave as one object: bind the group and every
    /// shape in it follows the same armature, without the rig having to be
    /// stamped on each one. Each shape is still deformed on its own points, so
    /// the arm bones move the arm and the leg bones move the leg — a layer
    /// follows the whole armature, weighted per point, not the single bone that
    /// happened to claim it.
    ///
    /// A layer with a rig of its own overrides what it inherits, so one shape
    /// inside a bound group can be driven by a different armature.
    private func posed(_ layer: Layer, under inherited: Int?) -> Layer {
        var out = layer
        let rig = layer.rig ?? inherited
        if let r = rig, armatures.indices.contains(r), let shape = layer.shape {
            out.shape = Skin.deform(shape, with: armatures[r])
        }
        if !layer.children.isEmpty {
            out.children = layer.children.map { posed($0, under: rig) }
        }
        return out
    }

    /// The layer as it is actually painted: posed, then wandered.
    ///
    /// Separate from `posed` on purpose. Hit testing and the selection box read
    /// `posed`, so a click lands on the line as drawn and the handles sit still
    /// — a box that shivered with the texture inside it would be a box you
    /// could not aim at, and the wander is a property of the *painting* rather
    /// than of the shape.
    func painted(_ layer: Layer) -> Layer { painted(posed(layer), wiggle: nil) }

    private func painted(_ layer: Layer, wiggle inherited: Wiggle?) -> Layer {
        var out = layer
        let w = layer.wiggle ?? inherited
        if let w, !w.isIdle, let shape = layer.shape {
            // Two seeds: one the layer keeps for the life of the drawing, one it
            // gets afresh on every frame. `boil` decides how much of each is
            // heard. The track rather than the id, where there is one, so the
            // same element on consecutive frames wanders from the same place
            // rather than jumping when a frame is duplicated.
            let identity = layer.track ?? layer.id
            out.shape = w.applied(to: shape,
                                  still: Wobble.seed(identity),
                                  moving: Wobble.seed(identity, id))
        }
        if !layer.children.isEmpty {
            out.children = layer.children.map { painted($0, wiggle: w) }
        }
        return out
    }

    /// Which armature, if any, drives this layer or anything inside it.
    ///
    /// Usually the layer's own — a group is bound as one thing — but a group
    /// still answers for a single shape inside it that was bound on its own, so
    /// nothing rigged can hide behind a shut group in the list.
    ///
    /// Only an armature that exists. A document written before rigs were cleared
    /// at every depth can hold an index pointing past the end, and a layer that
    /// merely *claims* to be rigged should not be able to say so.
    func rigIndex(of layer: Layer) -> Int? {
        if let r = layer.rig, armatures.indices.contains(r) { return r }
        for child in layer.children { if let r = rigIndex(of: child) { return r } }
        return nil
    }
}

// MARK: - Editing the armature

extension AppModel {
    var armatures: [Skeleton] {
        get { frame.armatures }
        set { frame.armatures = newValue }
    }

    var hasRig: Bool { !frame.armatures.isEmpty }
    var rigIsPosed: Bool { frame.armatures.contains { $0.isPosed } }

    // MARK: Placing bones

    /// Chaining a child, or starting a new armature.
    ///
    /// Every bone claims the layers it lies inside, not just the first one of a
    /// new rig, and a bone is judged by its **whole length** rather than by one
    /// endpoint. Testing only the origin means a chain started at a shoulder —
    /// naturally just outside the limb it drives — claims nothing, and no later
    /// bone can recover it: the drawing simply never moves.
    func addBone(from a: CGPoint, to b: CGPoint, rig: Int?, parent: Int?) {
        commit()
        var rigs = frame.armatures
        let r: Int
        if let rig, let parent, rigs.indices.contains(rig) {
            rigs[rig].addBone(from: a, to: b, parent: parent)
            r = rig
        } else {
            var skeleton = Skeleton()
            skeleton.addBone(from: a, to: b, parent: nil)
            rigs.append(skeleton)
            r = rigs.count - 1
        }
        frame.armatures = rigs
        activeRig = r
        if let bone = frame.armatures[r].bones.last { claim(for: r, bone: bone) }
        invalidateThumbnail()
    }

    /// What a new bone binds itself to.
    ///
    /// ## What you pointed at, if you pointed at anything
    ///
    /// A selection is an answer already given. If layers are selected when a
    /// bone goes down, those are what the armature takes — whole, and a group as
    /// one thing. Nothing is measured, so nothing is unpredictable: the same
    /// gesture over the same drawing binds the same layers every time.
    ///
    /// ## Otherwise, what the bone lies inside
    ///
    /// With nothing selected, enclosure decides, judged by the bone's **whole
    /// length** rather than by one endpoint — a chain started at a shoulder is
    /// naturally just outside the limb it drives, and testing the origin alone
    /// meant it claimed nothing and no later bone could recover it.
    ///
    /// Each layer is tested as one object, a group by the union of the shapes
    /// inside it, and a group that qualifies is taken whole rather than
    /// descended into. A group is one thing on the canvas, and a rig that had to
    /// find the particular shape under the bone made binding a grouped drawing a
    /// matter of where exactly the bone fell — which is the inconsistency this
    /// replaces.
    ///
    /// It never takes a layer another rig already holds: with every bone
    /// claiming, silent theft would be far too easy, and re-homing is what
    /// click-to-bind is for.
    private func claim(for rig: Int, bone: Bone) {
        var layers = frame.layers
        var touched = false

        func take(_ id: UUID) {
            LayerTree.mutate(id, in: &layers) {
                guard $0.rig == nil || $0.rig == rig else { return }
                $0.rig = rig
                touched = true
            }
        }

        // The outermost of the selection, so selecting a group and a shape
        // inside it binds the group once rather than twice.
        let chosen = LayerTree.outermost(selection, in: frame.layers)
        if !chosen.isEmpty {
            for l in chosen where l.visible { take(l.id) }
            if touched { frame.layers = layers }
            return
        }

        let samples = 8
        let probes = (0...samples).map { s -> CGPoint in
            let t = CGFloat(s) / CGFloat(samples)
            return CGPoint(x: bone.origin.x + (bone.tip.x - bone.origin.x) * t,
                           y: bone.origin.y + (bone.tip.y - bone.origin.y) * t)
        }
        func encloses(_ layer: Layer) -> Bool {
            guard let area = filledArea(of: layer) else { return false }
            let inside = probes.filter { area.contains($0, using: .winding) }.count
            return CGFloat(inside) / CGFloat(probes.count) >= 0.5
        }
        func walk(_ layers: [Layer]) {
            for l in layers where l.visible {
                if encloses(l) { take(l.id); continue }
                // Only worth descending when the layer as a whole missed: a
                // group that qualified is already taken, whole.
                if !l.children.isEmpty { walk(l.children) }
            }
        }
        walk(frame.layers)
        if touched { frame.layers = layers }
    }

    /// The layer's own filled path, in rest space.
    ///
    /// `CGPath.contains` is exact on curves, so enclosure has a real answer here
    /// where the prototype had to approximate a polygon. Only shapes that
    /// actually enclose an area can own a pose — an open construction line has
    /// no inside for a bone to be in.
    func filledArea(of layer: Layer) -> CGPath? {
        if let shape = layer.shape { return shape.hasFillableArea ? shape.cgPath : nil }
        // A group's area is the areas inside it, as one path — so a bone is
        // inside the group exactly when it is inside something the group holds,
        // and the gaps between those shapes are still outside. Subpaths, not a
        // bounding box, which would swallow the whole space they span.
        guard !layer.children.isEmpty else { return nil }
        let path = CGMutablePath()
        var any = false
        for kid in layer.children where kid.visible {
            guard let area = filledArea(of: kid) else { continue }
            path.addPath(area)
            any = true
        }
        return any ? path : nil
    }

    /// The objects enclosing `p`, frontmost first — a group counting as one, so
    /// a click binds or releases a grouped drawing whole.
    func layersEnclosing(_ p: CGPoint) -> [UUID] {
        var out: [UUID] = []
        func walk(_ layers: [Layer]) {
            for l in layers.reversed() where l.visible {
                if filledArea(of: l)?.contains(p, using: .winding) ?? false { out.append(l.id) }
                else if !l.children.isEmpty { walk(l.children) }
            }
        }
        walk(frame.layers)
        return out
    }

    /// Every posed shape a layer draws, itself or through what it holds.
    ///
    /// A group has no geometry of its own, so anything that wants to outline one
    /// — the ownership highlight, the hover — has to ask what is inside it.
    func posedShapes(of layer: Layer) -> [Shape2D] {
        var out: [Shape2D] = []
        func walk(_ layer: Layer) {
            if let s = layer.shape { out.append(s) }
            for kid in layer.children where kid.visible { walk(kid) }
        }
        walk(frame.posed(layer))
        return out
    }

    /// The explicit override, for everything enclosure gets wrong — a button on a
    /// sleeve, a highlight, a layer the rig only passes beside.
    func toggleRigMembership(layerAt id: UUID) {
        guard let r = targetRig else { return }
        commit()
        var layers = frame.layers
        LayerTree.mutate(id, in: &layers) { $0.rig = $0.rig == r ? nil : r }
        frame.layers = layers
        invalidateThumbnail()
    }

    /// Whether this layer is driven by an armature that is currently on screen.
    ///
    /// Keyed to what is shown rather than to `activeRig`: with the highlight on
    /// the last rig *touched*, a layer could carry the rig's colour while its
    /// bones were hidden, which says the opposite of the truth.
    func isOwnedByRigOnScreen(_ layer: Layer) -> Bool {
        guard let r = layer.rig else { return false }
        return rigsOnScreen.contains(r)
    }

    /// The armature a click-to-bind acts on.
    ///
    /// Derived from the selection first, so it can never be a rig you cannot
    /// see: binding a layer to an off-screen armature is an edit with no visible
    /// result and no obvious way back.
    var targetRig: Int? {
        let shown = rigsOnScreen
        if shown.count == 1 { return shown.first }
        if let r = activeRig, shown.contains(r) { return r }
        return shown.sorted().first ?? activeRig
    }

    // MARK: Posing

    /// Hit testing runs against the posed skeleton, which is what is on screen.
    func boneTip(near p: CGPoint, within r: CGFloat) -> (rig: Int, bone: Int)? {
        var best: (rig: Int, bone: Int)?
        var bestD = r
        for ri in frame.armatures.indices {
            for bi in frame.armatures[ri].bones.indices {
                let d = p.dist(frame.armatures[ri].bones[bi].tip)
                if d <= bestD { bestD = d; best = (ri, bi) }
            }
        }
        return best
    }

    func boneRoot(near p: CGPoint, within r: CGFloat) -> (rig: Int, bone: Int)? {
        var best: (rig: Int, bone: Int)?
        var bestD = r
        for ri in frame.armatures.indices {
            for bi in frame.armatures[ri].bones.indices where frame.armatures[ri].bones[bi].isRoot {
                let d = p.dist(frame.armatures[ri].bones[bi].origin)
                if d <= bestD { bestD = d; best = (ri, bi) }
            }
        }
        return best
    }

    /// How far up the chain IK is allowed to reach. Three is enough for a limb
    /// without the whole body swinging from a fingertip.
    var ikDepth: Int { 3 }

    func poseTip(rig: Int, bone: Int, to p: CGPoint, stretch: Bool) {
        guard frame.armatures.indices.contains(rig) else { return }
        var rigs = frame.armatures
        if poseWithIK {
            rigs[rig].reach(bone, to: p, depth: ikDepth)
        } else {
            rigs[rig].aim(bone, at: p, stretch: stretch)
        }
        frame.armatures = rigs
        invalidateThumbnail()
    }

    func poseRoot(rig: Int, bone: Int, to p: CGPoint) {
        guard frame.armatures.indices.contains(rig) else { return }
        var rigs = frame.armatures
        rigs[rig].translateRoot(bone, to: p)
        frame.armatures = rigs
        invalidateThumbnail()
    }

    /// Which armatures the bones on screen are scoped to.
    ///
    /// The rig belonging to the selected layer, so a frame carrying several does
    /// not put all of them over the drawing at once. With nothing selected it
    /// falls back to the one last placed or posed — otherwise building a rig from
    /// scratch would mean building it blind, since a bone claims by enclosure and
    /// need not touch anything already selected.
    var rigsOnScreen: Set<Int> {
        var out: Set<Int> = []
        for layer in frame.layers.flatMap({ $0.flattened() }) where selection.contains(layer.id) {
            if let r = layer.rig, frame.armatures.indices.contains(r) { out.insert(r) }
        }
        if out.isEmpty, let r = activeRig, frame.armatures.indices.contains(r) { out.insert(r) }
        return out
    }

    // MARK: Ghosting

    var hasRigGhost: Bool { !rigGhost.isEmpty }

    /// Snapshots the pose as it stands, or clears the snapshot.
    ///
    /// Overlaps with onion skin, deliberately: onion shows the *neighbouring
    /// frames*, and this shows where this frame's own pose was a moment ago,
    /// which is what you want while pushing one limb around.
    func toggleRigGhost() {
        if hasRigGhost { rigGhost = []; return }
        rigGhost = frame.layers.compactMap { layer in
            guard layer.rig != nil else { return nil }
            return frame.posed(layer).shape
        }
    }

    // MARK: The bar's actions

    func resetRigPose() {
        guard rigIsPosed else { return }
        commit()
        var rigs = frame.armatures
        for i in rigs.indices { rigs[i].resetPose() }
        frame.armatures = rigs
        invalidateThumbnail()
    }

    /// Takes the armatures out and releases every layer they held. The drawing
    /// itself is untouched — it was never written to, so what is left is exactly
    /// the rest pose.
    func deleteRig() {
        guard hasRig else { return }
        commit()
        frame.armatures = []
        // Every depth. Clearing only the top of the stack left a grouped shape
        // pointing at an armature that no longer exists — harmless to draw,
        // since posing checks the index, but the layer still called itself
        // rigged and the next armature would silently inherit it.
        func clear(_ layers: inout [Layer]) {
            for i in layers.indices {
                layers[i].rig = nil
                var kids = layers[i].children
                guard !kids.isEmpty else { continue }
                clear(&kids)
                layers[i].children = kids
            }
        }
        var layers = frame.layers
        clear(&layers)
        frame.layers = layers
        activeRig = nil
        rigGhost = []
        invalidateThumbnail()
    }
}
