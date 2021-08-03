
/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Main view controller for the AR experience.
*/

import ARKit
import SceneKit
import UIKit

class ViewController: UIViewController, ARSCNViewDelegate, WebSocketConnectionDelegate {
    
    @IBOutlet var sceneView: ARSCNView!
    
    @IBOutlet weak var blurView: UIVisualEffectView!

    
    let imageView = UIImageView()
    let shapeLayer1 = CAShapeLayer()
    let shapeLayer2 = CAShapeLayer()
    var rRegion = RectRegion(with: 1.0)
    var audioState:AudioState = .path
    let knockPlayer = KnockPlayer()
    
    /// The view controller that displays the status and "restart experience" UI.
    lazy var statusViewController: StatusViewController = {
        return children.lazy.compactMap({ $0 as? StatusViewController }).first!
    }()
    
    /// A serial queue for thread safety when modifying the SceneKit node graph.
    let updateQueue = DispatchQueue(label: Bundle.main.bundleIdentifier! +
        ".serialSceneKitQueue")
    
    /// Convenience accessor for the session owned by ARSCNView.
    var session: ARSession {
        return sceneView.session
    }
    
    // MARK: - View Controller Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        sceneView.addSubview(imageView)
        sceneView.debugOptions = [.showFeaturePoints, .showWorldOrigin ]
        sceneView.delegate = self
        sceneView.session.delegate = self

        // Hook up status view controller callback(s).
        statusViewController.restartExperienceHandler = { [unowned self] in
            self.restartExperience()
        }
        
        let sz = CGSize(width: view.bounds.width, height: view.bounds.width)
        imageView.frame = CGRect(x:0 , y:(view.bounds.height-sz.width-50), width: sz.width, height: sz.width)
        loadMap("image00.png")
        rRegion = RectRegion(with:6.0, and:imageView)
        imageView.alpha = 0.5
        view.layer.addSublayer(shapeLayer1)
        view.layer.addSublayer(shapeLayer2)
        
        sceneView.addSubview(xyzLabel)
        xyzLabel.frame = CGRect(x:50,y:50,width:100,height:250)
        xyzLabel.lineBreakMode = .byWordWrapping // notice the 'b' instead of 'B'
        xyzLabel.numberOfLines = 0
        xyzLabel.text = "(x,y,x): "
        
//        let x=150,y=40,w=100,h=30
//
//        startBtn = addButton(x:x, y:y, w:w, h:h, title: "Start", color: .blue, selector: #selector(startEnd))
        let ip = "172.20.220.182", port = "8001"
//        webSocketTask = WebSocketTaskConnection(url: URL(string: "ws://" + ip + ":" + port)!)
////        webSocketTask = WebSocketTaskConnection(url: URL(string: "ws://10.0.0.19:8000")!)
//        webSocketTask?.delegate = self
//        webSocketTask?.connect()
//        webSocketTask?.send(text: "Hello Socket, are you there?")
//        webSocketTask?.listen()
        webSocketTask = setWebSocket(ip,port)
        
        let x = 20, y = 50, w = 200, h = 30
        _ = addButton(x:x, y:y, w:w, h:h, title: "Connect to Server", color: .blue, selector: #selector(setWebSocketServer))
    }
    
    func setWebSocket(_ ip:String, _ port:String) -> WebSocketTaskConnection{
        let webSocketTask = WebSocketTaskConnection(url: URL(string: "ws://" + ip + ":" + port)!)
        webSocketTask.delegate = self
        webSocketTask.connect()
        webSocketTask.send(text: "Hello Socket, are you there?")
        webSocketTask.listen()
        return webSocketTask;
    }
    

    
//    var startBtn = UIButton()
    
    let xyzLabel = UILabel()
    
    var imgName = ""
    var rW:CGFloat=1, rH:CGFloat = 1
    
    func loadMap(_ im:String){
        imgName = im
        imageView.image = UIImage(named: im,  in: Bundle(for: type(of:self)), compatibleWith: nil)
        
        rW = imageView.frame.width/imageView.image!.size.width
        rH = imageView.frame.height/imageView.image!.size.height
    }
    

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Prevent the screen from being dimmed to avoid interuppting the AR experience.
        UIApplication.shared.isIdleTimerDisabled = true

        // Start the AR experience
        resetTracking()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        session.pause()
    }

    // MARK: - Session management (Image detection setup)
    
    /// Prevents restarting the session while a restart is in progress.
    var isRestartAvailable = true

    /// Creates a new AR configuration to run on the `session`.
    /// - Tag: ARReferenceImage-Loading
    
    var haveImageAnchor = false
    func resetTracking() {
        haveImageAnchor = false
        
        guard let referenceImages = ARReferenceImage.referenceImages(inGroupNamed: "AR Resources", bundle: nil) else {
            fatalError("Missing expected asset catalog resources.")
        }
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.detectionImages = referenceImages
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])

        statusViewController.scheduleMessage("Look around to detect images", inSeconds: 7.5, messageType: .contentPlacement)
    }
    
    func getPathCircle(_ pos: CGPoint, _ r:CGFloat) -> UIBezierPath{
        return UIBezierPath(arcCenter: pos, radius:r,startAngle: 0.0,endAngle: CGFloat.pi * 2, clockwise: true)
    }
    
    func getPathLine(_ p1: CGPoint,_ p2: CGPoint) -> UIBezierPath{
        let path = UIBezierPath()
        path.move(to: p1)
        path.addLine(to: p2)
        return path
    }
    
    func drawPath(_ layer:CAShapeLayer, _ paths:[UIBezierPath]){
        let shapeLayerPath = UIBezierPath()
        for path in paths{
            shapeLayerPath.append(path)
        }
        shapeLayerPath.stroke()
        layer.path = shapeLayerPath.cgPath
    }
    
    func clearPath(_ layer:CAShapeLayer){
        let shapeLayerPath = UIBezierPath()
        shapeLayerPath.stroke()
        layer.path = shapeLayerPath.cgPath
    }
    
    func setLayerParams(_ layer:CAShapeLayer, rect f:CGRect, lineWidth w:CGFloat, strokeColor color:CGColor){
        layer.frame = f
        layer.lineWidth = w
        layer.strokeColor = color
        layer.fillColor = nil
    }
    
    func drawCircle(_ layer:CAShapeLayer, _ pos:CGPoint,_ r:CGFloat = 5, color: CGColor = UIColor.green.cgColor) {
        let path = getPathCircle(pos,r)
        setLayerParams(layer,rect: view.frame, lineWidth: 3.0, strokeColor: color)
        path.stroke()
        layer.path = path.cgPath
    }
        
    func drawArrow(_ layer:CAShapeLayer, _ pos:CGPoint,theta:CGFloat,color: CGColor = UIColor.red.cgColor) {
        var paths = [UIBezierPath]()
        paths.append(getPathCircle(pos,3.0))
        let length:CGFloat = 50
        paths.append(getPathLine(pos,CGPoint(x:pos.x + length*cos(theta), y: pos.y + length*sin(theta))))
        
        setLayerParams(layer,rect: view.frame, lineWidth: 3.0, strokeColor: color)
        drawPath(layer, paths)
    }
//    var start = false
    var t0 = clock()
    let stepSize:Double = 0.01
//
//    @objc func startEnd(){
//        start = !start
//        if start{
//            t0 = clock()
//            dateAtStart = Date()
//        }
//    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {

        let c3 = frame.camera.transform.columns.3
        let theta:Float = frame.camera.eulerAngles.y + Float.pi
        
        xyzLabel.text = """
        (x,y,z):
        \(String(format: "%.3f", c3.x))
        \(String(format: "%.3f", c3.y))
        \(String(format: "%.3f", c3.z))
        
        theta: \(String(format: "%.1f", theta*180/Float.pi))
        """
        
        var (x0,y0) = rRegion.pixLoc(meter:CGFloat(c3.z),meter:CGFloat(c3.x))
        x0 += imageView.frame.minX
        y0 += imageView.frame.minY
        drawArrow(shapeLayer1, CGPoint(x:x0,y:y0),theta: CGFloat(-theta))
        if haveImageAnchor {
            moved(CGFloat(c3.z),CGFloat(c3.x), CGFloat(theta))
        }
        let diff = Double(clock() - t0) / Double(CLOCKS_PER_SEC)
        if diff >= stepSize{
            t0 = clock()
            let r = Record(x:c3.z, y:c3.x, theta: theta,t:Date().timeIntervalSince(dateAtStart))
            trialRecord.append(r)
            if haveImageAnchor && running{
                webSocketTask?.send(text: "\(String(format: "%.3f", r.x)) \(String(format: "%.3f", r.y)) \(String(format: "%.3f", r.theta)) \(String(format: "%.3f", r.t))")
            }
        }
    }
//    var record = Record(x:0,y:0,theta: 0, t:0)
    
    func setPlaybackStateTo(_ state: Bool) {
          Synth.shared.volume = state ? 0.5 : 0
          if !state { Synth.shared.frequency = 0 }
    }
    func setSynthParametersFrom(_ frequency: Float, amplitude:Float = 1.0) {
        Oscillator.amplitude = amplitude
        Synth.shared.frequency = frequency
    }
    
    var isInBG = false
    var trialRecord = [Record]()
    var param = PozyxParam()
    var dateAtStart = Date()
    func moved(_ x:CGFloat, _ y: CGFloat, _ theta: CGFloat ) {
        Synth.shared.tryStartEngine()
        clearPath(shapeLayer2)
        let (u,v) = rRegion.pixLoc(meter:x,meter:y)
        let val = rRegion.pixVal(pix:u,pix:v)
        if val < 0 { // outside of map
            Synth.shared.stopEngine()
            knockPlayer.play()
            clearPath(shapeLayer2)
            return
        }
        if val < 250 {  // tag in background
            audioState = .background
            setPlaybackStateTo(false)
            knockPlayer.stop()
        }
        else {
            var (u1,v1,length) = self.rRegion.reachGray(u,v, theta)
            if length > 0 {
//                var (x2,y2) = self.rRegion.pixLoc(x1,y1)
                u1 += self.imageView.frame.minX
                v1 += self.imageView.frame.minY
                self.drawCircle(self.shapeLayer2,CGPoint(x:u1,y:v1))
            }
            Synth.shared.tryStartEngine()
            setSynthParametersFrom(param.getFreq(length),amplitude: 1)
            audioState = .path
            setPlaybackStateTo(true)
            knockPlayer.stop()
        }
    }
    
    
    // MARK: - ARSCNViewDelegate (Image detection results)
    /// - Tag: ARImageAnchor-Visualizing
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {

        guard let imageAnchor = anchor as? ARImageAnchor else { return }
        let referenceImage = imageAnchor.referenceImage
        updateQueue.async {
            
            // Create a plane to visualize the initial position of the detected image.
            let plane = SCNPlane(width: referenceImage.physicalSize.width,
                                 height: referenceImage.physicalSize.height)
            let planeNode = SCNNode(geometry: plane)
            planeNode.opacity = 0.25
            
            /*
             `SCNPlane` is vertically oriented in its local coordinate space, but
             `ARImageAnchor` assumes the image is horizontal in its local space, so
             rotate the plane to match.
             */
//            planeNode.eulerAngles.x = -.pi / 2  //I like the image on the floor
            
            /*
             Image anchors are not tracked after initial detection, so create an
             animation that limits the duration for which the plane visualization appears.
             */
            planeNode.runAction(self.imageHighlightAction)
            
            // Add the plane visualization to the scene.
            node.addChildNode(planeNode)
            /*
             Move world origin to the Image anchor,   Huiying Shen.
             Other options:  add more image anchor for location verification. Then world origin is not moved.
             */
            self.session.setWorldOrigin(relativeTransform: simd_float4x4(planeNode.worldTransform))
            self.haveImageAnchor = true
        }

        DispatchQueue.main.async {
            let imageName = referenceImage.name ?? ""
            self.statusViewController.cancelAllScheduledMessages()
            self.statusViewController.showMessage("Detected image “\(imageName)”")
            
                       
        }
    }

    var imageHighlightAction: SCNAction {
        return .sequence([
            .wait(duration: 0.25),
            .fadeOpacity(to: 0.85, duration: 0.25),
            .fadeOpacity(to: 0.15, duration: 0.25),
            .fadeOpacity(to: 0.85, duration: 0.25),
            .fadeOut(duration: 0.5),
            .removeFromParentNode()
        ])
    }
    
    
    @objc func setWebSocketServer() {
        let model = UIAlertController(title: "WebServer", message: "", preferredStyle: .alert)
        model.addTextField { (textField) in
            textField.placeholder = "host name/ip address"
            textField.textColor = .blue
            textField.text = "172.20.220.182"
        }
        model.addTextField { (textField) in
            textField.placeholder = "port"
            textField.textColor = .blue
            textField.text = "8001"
        }
        let save = UIAlertAction(title: "Save", style: .default) { (alertAction) in
            let host = model.textFields![0] as UITextField
            let port = model.textFields![1] as UITextField
            self.webSocketTask =  self.setWebSocket(host.text!,port.text!)
            
        }

        model.addAction(save)
        model.addAction(UIAlertAction(title: "Cancel", style: .default) { (alertAction) in
        })
        
        self.present(model, animated:true, completion: nil)
    }
    
    @objc func saveTrialSession() {
           
        let model = UIAlertController(title: "Save Trial Data", message: "", preferredStyle: .alert)
        model.addTextField { (textField) in
            textField.placeholder = "File Name"
            textField.textColor = .blue
        }
        let save = UIAlertAction(title: "Save", style: .default) { (alertAction) in
            
            let fn = model.textFields![0].text ?? "tmp"
            var out = self.imgName + "\n"
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .medium
            out += formatter.string(from: self.dateAtStart) + "\n"
            for r in self.trialRecord{
                out += "\(String(format: "%.2f",r.x)), \(String(format: "%.2f", r.y)) "
                out += "\(String(format: "%.2f",r.theta)), \(String(format: "%.2f", r.t))\n"
            }
            self.writeTo(fn: "trial_" + fn + ".txt", dat: out)
        }
        
        model.addAction(save)
        model.addAction(UIAlertAction(title: "Cancel", style: .default) { (alertAction) in })
         
        self.present(model, animated:true, completion: nil)
    }
    
    func writeTo(fn:String,  dat:String){
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = dir.appendingPathComponent(fn)
            //writing
            do {
                try dat.write(to: fileURL, atomically: false, encoding: .utf8)
            }
            catch {/* error handling here */}
        }
    }
    
    func addButton(x:Int, y: Int, w: Int, h: Int, title: String, color: UIColor, selector: Selector) -> UIButton{
        let btn =  UIButton()
        btn.frame = CGRect (x:x, y:y, width:w, height:h)
        btn.setTitle(title, for: UIControl.State.normal)
        btn.setTitleColor(color, for: .normal)
        btn.backgroundColor = .lightGray
        btn.addTarget(self, action: selector, for: UIControl.Event.touchUpInside)
        self.view.addSubview(btn)
        buttons.append(btn)
        return btn
    }
    var webSocketTask:WebSocketTaskConnection?
    
    var buttons = [UIButton]()
    var running = false
    func onConnected(connection: WebSocketConnection) {
        print("connected: ", connection)
    }
    
    func onDisconnected(connection: WebSocketConnection, error: Error?) {
        print("disconnected")
    }
    
    func onError(connection: WebSocketConnection, error: Error) {
        
    }
    
    func onMessage(connection: WebSocketConnection, text: String) {
        print("received text: ", text)
        if text.contains("START"){
            webSocketTask?.send(text: "Start Streaming, ......")
            running = true
            t0 = clock()
            dateAtStart = Date()
        }
        if text.contains("STOP"){
            webSocketTask?.send(text: "Stop Streaming, ......")
            running = false
        }
    }
    
    func onMessage(connection: WebSocketConnection, data: Data) {
        print("received data: ", data)
    }
    
    
}
