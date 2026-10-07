import UIKit
import SpriteKit

// MARK: - App entry

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.rootViewController = GameViewController()
        w.makeKeyAndVisible()
        window = w
        return true
    }
}

// MARK: - View controller

final class GameViewController: UIViewController {
    private var started = false

    override func loadView() {
        let v = SKView()
        v.isMultipleTouchEnabled = true
        view = v
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !started, view.bounds.width > view.bounds.height,
              let skView = view as? SKView else { return }
        started = true
        // Fixed world height so the game looks the same on every device.
        let h: CGFloat = 400
        let w = h * view.bounds.width / view.bounds.height
        let scene = GameScene(size: CGSize(width: w, height: h))
        scene.scaleMode = .aspectFill
        skView.ignoresSiblingOrder = true
        skView.presentScene(scene)
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
}

// MARK: - Game types

enum Cat {
    static let player: UInt32 = 1 << 0
    static let ground: UInt32 = 1 << 1
    static let coin: UInt32   = 1 << 2
    static let enemy: UInt32  = 1 << 3
    static let goal: UInt32   = 1 << 4
}

enum Control { case left, right, jump }

/// A simple patrolling enemy (original design: a grumpy brown block).
final class Walker: SKSpriteNode {
    var minX: CGFloat = 0
    var maxX: CGFloat = 0
    var dir: CGFloat = -1

    init(at p: CGPoint, range: CGFloat) {
        super.init(texture: nil,
                   color: SKColor(red: 0.55, green: 0.30, blue: 0.15, alpha: 1),
                   size: CGSize(width: 28, height: 26))
        position = p
        minX = p.x - range
        maxX = p.x + range
        zPosition = 5

        for ex in [-6.0, 6.0] as [CGFloat] {
            let eye = SKSpriteNode(color: .white, size: CGSize(width: 7, height: 8))
            eye.position = CGPoint(x: ex, y: 3)
            let pupil = SKSpriteNode(color: .black, size: CGSize(width: 3, height: 4))
            pupil.position = CGPoint(x: 0, y: -1)
            eye.addChild(pupil)
            addChild(eye)
        }

        let body = SKPhysicsBody(rectangleOf: size)
        body.allowsRotation = false
        body.friction = 0
        body.restitution = 0
        body.categoryBitMask = Cat.enemy
        body.collisionBitMask = Cat.ground
        body.contactTestBitMask = 0
        physicsBody = body
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Scene

final class GameScene: SKScene, SKPhysicsContactDelegate {
    private let groundTop: CGFloat = 60
    private let worldWidth: CGFloat = 3300

    private let player = SKSpriteNode(color: SKColor(red: 0.85, green: 0.10, blue: 0.10, alpha: 1),
                                      size: CGSize(width: 28, height: 36))
    private let skin = SKNode()
    private let cam = SKCameraNode()
    private let coinLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let messageLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")

    private var buttons: [Control: SKShapeNode] = [:]
    private var held: [UITouch: Control] = [:]
    private var walkers: [Walker] = []

    private var jumpRequested = false
    private var isOver = false
    private var canRestart = false
    private var coins = 0
    private var totalCoins = 0

    // MARK: Setup

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.36, green: 0.62, blue: 0.98, alpha: 1)
        physicsWorld.gravity = CGVector(dx: 0, dy: -15)
        physicsWorld.contactDelegate = self
        view.isMultipleTouchEnabled = true

        buildLevel()
        buildPlayer()
        buildHUD()
        updateHUD()
    }

    private func buildLevel() {
        // Clouds
        for cx in stride(from: 150.0, to: 3300.0, by: 330.0) {
            let cloud = SKShapeNode(ellipseOf: CGSize(width: 110, height: 40))
            cloud.fillColor = SKColor(white: 1, alpha: 0.85)
            cloud.strokeColor = .clear
            cloud.position = CGPoint(x: CGFloat(cx), y: 300 + CGFloat(Int(cx) % 3) * 25)
            cloud.zPosition = -10
            addChild(cloud)
        }

        // Invisible side walls
        addBlock(centerX: -10, centerY: 300, width: 20, height: 800, color: .clear)
        addBlock(centerX: worldWidth + 10, centerY: 300, width: 20, height: 800, color: .clear)

        // Ground segments (gaps between them are pits)
        addGround(from: 0, to: 700)
        addGround(from: 790, to: 1500)
        addGround(from: 1590, to: 2350)
        addGround(from: 2440, to: worldWidth)

        // Platforms
        addPlatform(x: 350, y: 140, width: 120)
        addPlatform(x: 520, y: 140, width: 100)
        addPlatform(x: 900, y: 140, width: 140)
        addPlatform(x: 1100, y: 140, width: 100)
        addPlatform(x: 1700, y: 140, width: 120)
        addPlatform(x: 1860, y: 200, width: 100)
        addPlatform(x: 2150, y: 140, width: 140)
        addPlatform(x: 2900, y: 140, width: 120)

        // Pipes
        addPipe(x: 600, height: 50)
        addPipe(x: 1300, height: 70)
        addPipe(x: 1950, height: 60)
        addPipe(x: 2600, height: 70)

        // Enemies
        for (x, r) in [(520.0, 60.0), (1000.0, 80.0), (1400.0, 45.0),
                       (1800.0, 100.0), (2250.0, 50.0), (2800.0, 100.0)] as [(CGFloat, CGFloat)] {
            let w = Walker(at: CGPoint(x: x, y: groundTop + 14), range: r)
            walkers.append(w)
            addChild(w)
        }

        // Coins
        addCoinRow(startX: 200, y: 100, count: 4, spacing: 35)
        addCoinRow(startX: 320, y: 185, count: 3, spacing: 30)
        addCoinRow(startX: 490, y: 185, count: 3, spacing: 30)
        addCoinRow(startX: 725, y: 150, count: 3, spacing: 20)
        addCoinRow(startX: 860, y: 185, count: 4, spacing: 30)
        addCoinRow(startX: 1075, y: 185, count: 2, spacing: 50)
        addCoinRow(startX: 1540, y: 150, count: 3, spacing: 20)
        addCoinRow(startX: 1680, y: 185, count: 3, spacing: 30)
        addCoinRow(startX: 1840, y: 245, count: 3, spacing: 30)
        addCoinRow(startX: 2100, y: 185, count: 4, spacing: 30)
        addCoinRow(startX: 2395, y: 150, count: 3, spacing: 20)
        addCoinRow(startX: 2860, y: 185, count: 3, spacing: 30)

        // Goal pole + flag
        let poleX: CGFloat = 3200
        let pole = SKSpriteNode(color: SKColor(white: 0.9, alpha: 1), size: CGSize(width: 8, height: 170))
        pole.position = CGPoint(x: poleX, y: groundTop + 85)
        let pb = SKPhysicsBody(rectangleOf: pole.size)
        pb.isDynamic = false
        pb.categoryBitMask = Cat.goal
        pb.collisionBitMask = 0
        pole.physicsBody = pb
        addChild(pole)

        let flag = SKSpriteNode(color: SKColor(red: 0.95, green: 0.8, blue: 0.1, alpha: 1),
                                size: CGSize(width: 34, height: 22))
        flag.position = CGPoint(x: poleX - 21, y: groundTop + 158)
        addChild(flag)
    }

    private func addBlock(centerX: CGFloat, centerY: CGFloat, width: CGFloat, height: CGFloat, color: SKColor) {
        let n = SKSpriteNode(color: color, size: CGSize(width: width, height: height))
        n.position = CGPoint(x: centerX, y: centerY)
        let body = SKPhysicsBody(rectangleOf: n.size)
        body.isDynamic = false
        body.friction = 0
        body.categoryBitMask = Cat.ground
        n.physicsBody = body
        addChild(n)
    }

    private func addGround(from x1: CGFloat, to x2: CGFloat) {
        let w = x2 - x1
        let cx = (x1 + x2) / 2
        addBlock(centerX: cx, centerY: groundTop / 2, width: w, height: groundTop,
                 color: SKColor(red: 0.55, green: 0.35, blue: 0.18, alpha: 1))
        let grass = SKSpriteNode(color: SKColor(red: 0.25, green: 0.7, blue: 0.25, alpha: 1),
                                 size: CGSize(width: w, height: 10))
        grass.position = CGPoint(x: cx, y: groundTop - 5)
        grass.zPosition = 1
        addChild(grass)
    }

    private func addPlatform(x: CGFloat, y: CGFloat, width: CGFloat) {
        addBlock(centerX: x, centerY: y, width: width, height: 20,
                 color: SKColor(red: 0.78, green: 0.38, blue: 0.2, alpha: 1))
    }

    private func addPipe(x: CGFloat, height: CGFloat) {
        addBlock(centerX: x, centerY: groundTop + height / 2, width: 50, height: height,
                 color: SKColor(red: 0.1, green: 0.55, blue: 0.2, alpha: 1))
    }

    private func addCoin(x: CGFloat, y: CGFloat) {
        let coin = SKShapeNode(circleOfRadius: 8)
        coin.fillColor = SKColor(red: 1, green: 0.85, blue: 0.1, alpha: 1)
        coin.strokeColor = SKColor(red: 0.9, green: 0.6, blue: 0.0, alpha: 1)
        coin.lineWidth = 2
        coin.position = CGPoint(x: x, y: y)
        coin.zPosition = 4
        let body = SKPhysicsBody(circleOfRadius: 8)
        body.isDynamic = false
        body.categoryBitMask = Cat.coin
        body.collisionBitMask = 0
        coin.physicsBody = body
        addChild(coin)
        totalCoins += 1
    }

    private func addCoinRow(startX: CGFloat, y: CGFloat, count: Int, spacing: CGFloat) {
        for i in 0..<count {
            addCoin(x: startX + CGFloat(i) * spacing, y: y)
        }
    }

    private func buildPlayer() {
        player.position = CGPoint(x: 80, y: groundTop + player.size.height / 2 + 1)
        player.zPosition = 10

        let cap = SKSpriteNode(color: SKColor(red: 0.6, green: 0.05, blue: 0.05, alpha: 1),
                               size: CGSize(width: 32, height: 8))
        cap.position = CGPoint(x: 2, y: 15)
        skin.addChild(cap)

        let eye = SKSpriteNode(color: .white, size: CGSize(width: 7, height: 9))
        eye.position = CGPoint(x: 6, y: 4)
        let pupil = SKSpriteNode(color: .black, size: CGSize(width: 3, height: 5))
        pupil.position = CGPoint(x: 1, y: 0)
        eye.addChild(pupil)
        skin.addChild(eye)

        player.addChild(skin)

        let body = SKPhysicsBody(rectangleOf: player.size)
        body.allowsRotation = false
        body.friction = 0
        body.restitution = 0
        body.linearDamping = 0
        body.categoryBitMask = Cat.player
        body.collisionBitMask = Cat.ground
        body.contactTestBitMask = Cat.coin | Cat.enemy | Cat.goal
        player.physicsBody = body
        addChild(player)
    }

    private func buildHUD() {
        addChild(cam)
        camera = cam
        cam.position = CGPoint(x: size.width / 2, y: size.height / 2)

        coinLabel.fontSize = 22
        coinLabel.horizontalAlignmentMode = .left
        coinLabel.verticalAlignmentMode = .center
        coinLabel.position = CGPoint(x: -size.width / 2 + 70, y: size.height / 2 - 34)
        coinLabel.zPosition = 100
        cam.addChild(coinLabel)

        messageLabel.fontSize = 34
        messageLabel.horizontalAlignmentMode = .center
        messageLabel.verticalAlignmentMode = .center
        messageLabel.position = CGPoint(x: 0, y: 20)
        messageLabel.zPosition = 100
        messageLabel.isHidden = true
        cam.addChild(messageLabel)

        let w = size.width, h = size.height
        makeButton(.left, title: "◀", at: CGPoint(x: -w / 2 + 110, y: -h / 2 + 70))
        makeButton(.right, title: "▶", at: CGPoint(x: -w / 2 + 215, y: -h / 2 + 70))
        makeButton(.jump, title: "▲", at: CGPoint(x: w / 2 - 110, y: -h / 2 + 70))
    }

    private func makeButton(_ control: Control, title: String, at p: CGPoint) {
        let node = SKShapeNode(rectOf: CGSize(width: 90, height: 90), cornerRadius: 18)
        node.fillColor = SKColor(white: 1, alpha: 0.3)
        node.strokeColor = SKColor(white: 1, alpha: 0.6)
        node.position = p
        node.zPosition = 100
        let label = SKLabelNode(text: title)
        label.fontSize = 36
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        node.addChild(label)
        cam.addChild(node)
        buttons[control] = node
    }

    private func updateHUD() {
        coinLabel.text = "Coins: \(coins)/\(totalCoins)"
    }

    // MARK: Touch controls

    private func control(at p: CGPoint) -> Control? {
        for (c, node) in buttons where node.frame.insetBy(dx: -15, dy: -15).contains(p) {
            return c
        }
        return nil
    }

    private var leftHeld: Bool { held.values.contains(.left) }
    private var rightHeld: Bool { held.values.contains(.right) }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isOver {
            if canRestart { restart() }
            return
        }
        for t in touches {
            if let c = control(at: t.location(in: cam)) {
                held[t] = c
                if c == .jump { jumpRequested = true }
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            held[t] = control(at: t.location(in: cam))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { held[t] = nil }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { held[t] = nil }
    }

    // MARK: Game loop

    private func isGrounded() -> Bool {
        let footY = player.position.y - player.size.height / 2
        var hit = false
        for dx in [-12.0, 0.0, 12.0] as [CGFloat] {
            let start = CGPoint(x: player.position.x + dx, y: footY + 2)
            let end = CGPoint(x: start.x, y: footY - 4)
            physicsWorld.enumerateBodies(alongRayStart: start, end: end) { body, _, _, _ in
                if body.categoryBitMask == Cat.ground { hit = true }
            }
        }
        return hit
    }

    override func update(_ currentTime: TimeInterval) {
        for w in walkers where w.parent != nil {
            if w.position.x < w.minX { w.dir = 1 }
            else if w.position.x > w.maxX { w.dir = -1 }
            w.physicsBody?.velocity.dx = w.dir * 60
        }

        guard !isOver, let body = player.physicsBody else { return }

        var dir: CGFloat = 0
        if leftHeld { dir -= 1 }
        if rightHeld { dir += 1 }
        body.velocity.dx = dir * 200
        if dir != 0 { skin.xScale = dir }

        if jumpRequested {
            jumpRequested = false
            if isGrounded() { body.velocity.dy = 700 }
        }

        if player.position.y < -60 { die() }
    }

    override func didSimulatePhysics() {
        let half = size.width / 2
        let maxX = max(worldWidth - half, half)
        cam.position = CGPoint(x: min(max(player.position.x, half), maxX), y: size.height / 2)
    }

    // MARK: Contacts

    func didBegin(_ contact: SKPhysicsContact) {
        guard !isOver else { return }
        let a = contact.bodyA, b = contact.bodyB
        let (first, second) = a.categoryBitMask < b.categoryBitMask ? (a, b) : (b, a)
        guard first.categoryBitMask == Cat.player else { return }

        switch second.categoryBitMask {
        case Cat.coin:
            second.node?.removeFromParent()
            coins += 1
            updateHUD()
        case Cat.enemy:
            if let enemy = second.node { handleEnemy(enemy) }
        case Cat.goal:
            win()
        default:
            break
        }
    }

    private func handleEnemy(_ enemy: SKNode) {
        let feet = player.position.y - player.size.height / 2
        if feet > enemy.position.y + 4 {
            enemy.removeFromParent()
            player.physicsBody?.velocity.dy = 420
        } else {
            die()
        }
    }

    // MARK: End states

    private func finish(_ text: String) {
        isOver = true
        held.removeAll()
        messageLabel.text = text
        messageLabel.isHidden = false
        run(.sequence([.wait(forDuration: 0.6), .run { [weak self] in self?.canRestart = true }]))
    }

    private func die() {
        guard !isOver else { return }
        player.physicsBody?.collisionBitMask = 0
        player.physicsBody?.contactTestBitMask = 0
        player.physicsBody?.velocity = CGVector(dx: 0, dy: 500)
        finish("Oops! Tap to retry")
    }

    private func win() {
        player.physicsBody?.velocity = CGVector(dx: 0, dy: 0)
        finish("You win! \(coins)/\(totalCoins) coins. Tap to replay")
    }

    private func restart() {
        let scene = GameScene(size: size)
        scene.scaleMode = scaleMode
        view?.presentScene(scene, transition: .fade(withDuration: 0.4))
    }
}
