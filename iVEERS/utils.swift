//
//  utils.swift
//  ARKitImageDetection
//
//  Created by Huiying Shen on 5/13/21.
//  Copyright © 2021 Apple. All rights reserved.
//

import UIKit
import AVFoundation

extension UIImage {

    func getPixelGray(_ x: Int, _ y: Int) -> Int {
        if x < 0 || y < 0 || x >= Int(self.size.width) || y >= Int(self.size.height) {return -1}
//        print("getPixelGray(), x, y = \(x), \(y)")
        if let pixelData = self.cgImage?.dataProvider?.data {
            let data: UnsafePointer<UInt8> = CFDataGetBytePtr(pixelData)
            let n: Int = ((Int(self.size.width) * y) + x) * 4
            return Int(0.3*Float(data[n+0]) + 0.59*Float(data[n+1]) + 0.11*Float(data[n+2]))
        }
        return -1  // maybe it's not a 4 channel image?
    }
}

class RectRegion{
    // white pixels in the map indicate path
    var map = UIImageView()
    var distPixRatio:CGFloat = 1
    var widthInMeter:CGFloat = 6.0
    var rW:CGFloat = 1
    var rH:CGFloat = 1
    let grayThrsh:Int = 250
    

    init(with widthInMeter:CGFloat){
        self.widthInMeter = widthInMeter
     }
    
    init(with widthInMeter:CGFloat, and map:UIImageView){
        self.widthInMeter = widthInMeter
        self.distPixRatio = map.frame.width/widthInMeter
        self.map = map;
        rW = map.frame.width/map.image!.size.width
        rH = map.frame.height/map.image!.size.height
    }

    func setMap(with map:UIImageView ){
        self.map = map;
        rW = map.frame.width/map.image!.size.width
        rH = map.frame.height/map.image!.size.height
    }
    
    func pixLoc(meter x:CGFloat,meter y:CGFloat) -> (CGFloat,CGFloat){
         let x1 = map.frame.width/2.0  + x*distPixRatio
         let y1 = map.frame.height/2.0 - y*distPixRatio
         return (x1,y1)
    }
    
    func pixVal(pix u:CGFloat, pix v:CGFloat) -> Int{
        map.image!.getPixelGray(Int(u/rW),Int(v/rH))
    }
    
    func reachGray(_ u:CGFloat, _ v:CGFloat, _ theta:CGFloat) -> (CGFloat,CGFloat,Float) {
        let val = map.image!.getPixelGray(Int(u/rW),Int(v/rH))
        if val < grayThrsh {return (u,u,-1)}
        var du = CGFloat(cos(-theta))*8
        var dv = CGFloat(sin(-theta))*8
        var u1 = u, v1 = v
        var b = false
        for _ in 1...3{
             (u1,v1,b) = reachGray1(pix:u1,pix:v1,du:du,dv:dv)
            if b {
                du = du/2
                dv = dv/2
            } else{
                return (u,v,-1)
            }
        }
        let lx = u1 - u
        let ly = v1 - v
        return (u1,v1, sqrt(Float(lx*lx + ly*ly))/Float(distPixRatio))
    }
    
    func reachGray1(pix u:CGFloat, pix v:CGFloat, du:CGFloat, dv:CGFloat) -> (CGFloat,CGFloat,Bool) {
        let nMax = 99
        var n = 0
        var u1 = u, v1 = v
        while n < nMax{
            let val = map.image!.getPixelGray(Int(u1/rW),Int(v1/rH))
            if val < grayThrsh {
                return (u1,v1,true)
            }
            n += 1
            u1 += du
            v1 += dv
        }
        return (u,v,false)
    }
    
}


class PozyxParam{
    var isExp = true
    var isHigh2Low = true
    var freqLow:Float = 300.0
    var freqHigh:Float = 1000.0
    var distMax:Float = 6.0  // cm
    var vol:Float = 0.8
    
    func getFreq(_ d: Float) -> Float{
        var f1 = freqLow, f2 = freqHigh
        if isHigh2Low {
            f2 = freqLow; f1 = freqHigh
        }
        if isExp {return freq_exp(d: d, f_min: f1, f_max: f2)}
        return freq_linear(d: d, f_min: f1, f_max: f2)
    }
    
    func freq_linear(d:Float, f_min:Float, f_max:Float) -> Float{
        return f_min + (f_max-f_min)*(d/distMax)
    }

    func freq_exp(d:Float, f_min:Float, f_max:Float) -> Float{
        return f_min*pow(f_max/f_min,d/distMax)
    }
}

enum AudioState{
    case outside,background,path
}

class KnockPlayer{
    var player = AVAudioPlayer()
    var isKnocking = false
    
    func _playKnock(vol: Float = 1.0){
        let url = URL(fileURLWithPath: Bundle.main.path(forResource: "knocking-single", ofType:"wav")!)
        do {
            self.player = try AVAudioPlayer(contentsOf: url)
            self.player.setVolume(vol, fadeDuration: 0.5)
            self.player.numberOfLoops = 0
            self.player.play()
        } catch {// couldn't load file :(
        }
    }
    
    func play(interval: Double = 0.5){
        if !self.isKnocking {
            self.isKnocking = true
            Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { timer in
                self._playKnock()
                if !self.isKnocking { timer.invalidate() }
            }
        }
    }
    
    func stop() {isKnocking = false}
}

struct Record{
    var x:Float, y:Float, theta:Float, t:Double
}
