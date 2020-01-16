//
//  EffectOpenGLFilter.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/9/27.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import UIKit
import GLKit
import CoreMedia
import CocoaLumberjack

class EffectOpenGLFilter: EffectFilter {

    var outputFormatDescription: CMFormatDescription?

    private var context: EAGLContext?

    // Input
    private var inputWidth: Int = 0
    private var inputHeight: Int = 0
    private var inputTexture: PixelBufferTexture!

    // Shader
    private var squareVertices: [GLfloat] = [
        -1, -1, // bottom left
        1, -1, // bottom right
        -1, 1, // top left
        1, 1, // top right
    ]
    private var textureVertices: [Float] = [
        0, 0, // bottom left
        1, 0, // bottom right
        0, 1, // top left
        1, 1, // top right
    ]
    
    private var filterProgram: ShaderProgram!
    private var filterPositionSlot = GLuint()
    private var filterTexturePositionSlot = GLuint()
    private var filterTextureUniform = GLint()
    private var textTextureUniform = GLint()
    private var textTextureName = GLuint()
    private var textProgressUniform = GLint()
    private var textProgress: TimeInterval = 0
    private var sequenceIn: TimeInterval = 0
    private var fadeInEndTime: TimeInterval = 0
    private var fadeOutStartTime: TimeInterval = 0
    private var sequenceOut: TimeInterval = 0

    private var imageTextureVertices: [Float] = [
        0, 0, // bottom left
        1, 0, // bottom right
        0, 1, // top left
        1, 1, // top right
    ]

    private let logoOffset: GLfloat = 10
    private let logoSize: GLfloat = 180 / 3
    private var logoPositionVertices: [GLfloat] = [ // before vertical flip
        -1, -1, // bottom left
        1, -1, // bottom right
        -1, 1, // top left
        1, 1, // top right
    ]
    private var logoTextureName = GLuint()
    
    private var animatorOffsetX: GLfloat = 0
    private let animatorOffsetY: GLfloat = 130
    private let animatorWidth: GLfloat = 324 / 2
    private let animatorHeight: GLfloat = 288 / 2
    private var animatorPositionVertices: [GLfloat] = [ // before vertical flip
        -1, -1, // bottom left
        1, -1, // bottom right
        -1, 1, // top left
        1, 1, // top right
    ]
    private var animatorTextureNames: [GLuint] = []
    private var animatorIndex = 0
    private var animatorCount = -1
    private var animatorStep = 3
    private var animatorPositionOrigin: GLfloat = 0
    private var animatorPositionCurrent: GLfloat = 0
    private var animatorProgress: GLfloat = 0.05
        
    private var directPassProgram: ShaderProgram!
    private var directPassPositionSlot = GLuint()
    private var directPassTexturePositionSlot = GLuint()
    private var directPassTextureUniform = GLint()

    // Output
    private var outputWidth: Int = 0
    private var outputHeight: Int = 0
    private var outputTexture: PixelBufferTexture!
    private var renderDestination: RenderDestination!

    deinit {
        reset()
    }

    init() {
        guard let context = EAGLContext(api: .openGLES2) else {
            DDLogError("Could not initialize OpenGL context")
            exit(1)
        }
        self.context = context
    }
    
    func prepare(with ratioMode: CameraRatioMode, positionMode: CameraPositionMode,
                 formatDescription: CMFormatDescription, retainedBufferCountHint: Int) {
        caculateDimensions(ratioMode: ratioMode,
                           positionMode: positionMode,
                           formatDescription: formatDescription)
        
        let oldContext = EAGLContext.current()
        if context !== oldContext {
            if !EAGLContext.setCurrent(context) {
                DDLogError("Could not set current OpenGL context with new context")
                exit(1)
            }
        }
        
        setupInput()
        if filterProgram == nil {
            compileFilterShaders()
            textTextureName = drawText("人生很短暂")
            setupProgress()
        }
        if directPassProgram == nil {
            compileDirectPassShaders()
            logoTextureName = loadTexture("logo.png")
            for i in 0..<4 {
                let filename = String(format: "walk%02d.png", i + 1)
                animatorTextureNames.append(loadTexture(filename))
            }
        }
        setupOutputTexture(retainedBufferCountHint: retainedBufferCountHint)
        if renderDestination == nil {
            setupRenderDestination()
        }
        renderDestination.setViewport(width: outputWidth, height: outputHeight)

        if oldContext !== context {
            if !EAGLContext.setCurrent(oldContext) {
                DDLogError("Could not set current OpenGL context with old context")
                exit(1)
            }
        }
    }

    func filter(pixelBuffer: CVPixelBuffer) -> CVPixelBuffer {
        let oldContext = EAGLContext.current()
        if context !== oldContext {
            if !EAGLContext.setCurrent(context) {
                DDLogError("Could not set current OpenGL context with new context")
                exit(1)
            }
        }

        let outputPixelBuffer = outputTexture.createTexture()
        outputTexture.bind(textureNo: GLenum(GL_TEXTURE0))
        renderDestination.attachTexture(name: outputTexture.textureName)

        // draw camera texture and text texture
        
        updateProgress()
        
        filterProgram.use()
        
        inputTexture.createTexture(from: pixelBuffer)
        inputTexture.bind(textureNo: GLenum(GL_TEXTURE1))
        glUniform1i(filterTextureUniform, 1)
        
        glActiveTexture(GLenum(GL_TEXTURE2))
        glBindTexture(GLenum(GL_TEXTURE_2D), textTextureName)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
        glUniform1i(textTextureUniform, 2)
        
        glUniform1f(textProgressUniform, GLfloat(textProgress))

        glEnableVertexAttribArray(filterPositionSlot)
        glVertexAttribPointer(filterPositionSlot,
                              2,
                              GLenum(GL_FLOAT),
                              GLboolean(UInt8(GL_FALSE)),
                              GLsizei(0),
                              &squareVertices)
        
        glEnableVertexAttribArray(filterTexturePositionSlot)
        glVertexAttribPointer(filterTexturePositionSlot,
                              2,
                              GLenum(GL_FLOAT),
                              GLboolean(UInt8(GL_FALSE)),
                              GLsizei(0),
                              &textureVertices)
        
        glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4)
        
        inputTexture.unbind()
        inputTexture.deleteTexture()
        glBindTexture(GLenum(GL_TEXTURE_2D), 0)
        
        // draw logo

        directPassProgram.use()

        glEnableVertexAttribArray(directPassPositionSlot)
        glVertexAttribPointer(directPassPositionSlot,
                              2,
                              GLenum(GL_FLOAT),
                              GLboolean(UInt8(GL_FALSE)),
                              GLsizei(0),
                              &logoPositionVertices)
        
        glEnableVertexAttribArray(directPassTexturePositionSlot)
        glVertexAttribPointer(directPassTexturePositionSlot,
                              2,
                              GLenum(GL_FLOAT),
                              GLboolean(UInt8(GL_FALSE)),
                              GLsizei(0),
                              &imageTextureVertices)
        
        glActiveTexture(GLenum(GL_TEXTURE1))
        glBindTexture(GLenum(GL_TEXTURE_2D), logoTextureName)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
        glUniform1i(directPassTextureUniform, 1)

        glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4)
        
        // draw png sequence
        
        updateAnimator()

        glVertexAttribPointer(directPassPositionSlot,
                              2,
                              GLenum(GL_FLOAT),
                              GLboolean(UInt8(GL_FALSE)),
                              GLsizei(0),
                              &animatorPositionVertices)
        
        glVertexAttribPointer(directPassTexturePositionSlot,
                              2,
                              GLenum(GL_FLOAT),
                              GLboolean(UInt8(GL_FALSE)),
                              GLsizei(0),
                              &imageTextureVertices)
        
        glActiveTexture(GLenum(GL_TEXTURE1))
        glBindTexture(GLenum(GL_TEXTURE_2D), animatorTextureNames[animatorIndex])
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
        glUniform1i(directPassTextureUniform, 1)

        glEnable(GLenum(GL_BLEND))
        glBlendFunc(GLenum(GL_SRC_ALPHA), GLenum(GL_ONE_MINUS_SRC_ALPHA))
        glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4)

        glFlush()
        
        outputTexture.unbind()
        outputTexture.deleteTexture()

        if oldContext !== context {
            if !EAGLContext.setCurrent(oldContext) {
                DDLogError("Could not set current OpenGL context with old context")
                exit(1)
            }
        }
        
        return outputPixelBuffer
    }
    
    private func caculateDimensions(ratioMode: CameraRatioMode,
                                    positionMode: CameraPositionMode,
                                    formatDescription: CMFormatDescription) {
        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
        let sourceWidth = Float(dimensions.width)
        let sourceHeight = Float(dimensions.height)
        let targetWidth = sourceWidth
        let targetHeight = targetWidth * Float(ratioMode.ratio)
        let fromY = ((sourceHeight - targetHeight) / 2) / sourceHeight
        let toY = 1.0 - fromY
        textureVertices[1] = fromY
        textureVertices[3] = fromY
        textureVertices[5] = toY
        textureVertices[7] = toY
        let fromX: Float = 0.0
        let toX: Float = 1.0
        if positionMode == .front {
            textureVertices[0] = toX
            textureVertices[2] = fromX
            textureVertices[4] = toX
            textureVertices[6] = fromX
        } else {
            textureVertices[0] = fromX
            textureVertices[2] = toX
            textureVertices[4] = fromX
            textureVertices[6] = toX
        }
        
        // bottom left
        logoPositionVertices[0] = 2 * (logoOffset / targetWidth) - 1
        logoPositionVertices[1] = 2 * ((targetHeight - logoOffset - logoSize) / targetHeight) - 1
        // bottom right
        logoPositionVertices[2] = 2 * ((logoOffset + logoSize) / targetWidth) - 1
        logoPositionVertices[3] = 2 * ((targetHeight - logoOffset - logoSize) / targetHeight) - 1
        // top left
        logoPositionVertices[4] = 2 * (logoOffset / targetWidth) - 1
        logoPositionVertices[5] = 2 * ((targetHeight - logoOffset) / targetHeight) - 1
        // top right
        logoPositionVertices[6] = 2 * ((logoOffset + logoSize) / targetWidth) - 1
        logoPositionVertices[7] = 2 * ((targetHeight - logoOffset) / targetHeight) - 1
        
        animatorOffsetX = -animatorWidth
        // bottom left
        animatorPositionVertices[0] = 2 * (animatorOffsetX / targetWidth) - 1
        animatorPositionVertices[1] = 2 * ((targetHeight - animatorOffsetY - animatorHeight) / targetHeight) - 1
        // bottom right
        animatorPositionVertices[2] = 2 * ((animatorOffsetX + animatorWidth) / targetWidth) - 1
        animatorPositionVertices[3] = 2 * ((targetHeight - animatorOffsetY - animatorHeight) / targetHeight) - 1
        // top left
        animatorPositionVertices[4] = 2 * (animatorOffsetX / targetWidth) - 1
        animatorPositionVertices[5] = 2 * ((targetHeight - animatorOffsetY) / targetHeight) - 1
        // top right
        animatorPositionVertices[6] = 2 * ((animatorOffsetX + animatorWidth) / targetWidth) - 1
        animatorPositionVertices[7] = 2 * ((targetHeight - animatorOffsetY) / targetHeight) - 1
        
        animatorPositionOrigin = animatorPositionVertices[0]
        animatorPositionCurrent = animatorPositionOrigin

        inputWidth = Int(sourceWidth)
        inputHeight = Int(sourceHeight)
        outputWidth = Int(targetWidth)
        outputHeight = Int(targetHeight)
    }

    private func setupInput() {
        guard let context = context else { return }
        inputTexture = PixelBufferTexture(width: inputWidth, height: inputHeight,
                                          retainedBufferCountHint: 0)
        inputTexture.createTextureCache(in: context)
    }
    
    private func compileFilterShaders() {
        filterProgram = ShaderProgram(vertexShaderName: "FilterVertex",
                                      fragmentShaderName: "FilterFragment")
        filterPositionSlot = filterProgram.attributeLocation(for: "a_position")
        filterTexturePositionSlot = filterProgram.attributeLocation(for: "a_texcoord")
        filterTextureUniform = filterProgram.uniformLocation(for: "u_texture")
        textTextureUniform = filterProgram.uniformLocation(for: "u_text_texture")
        textProgressUniform = filterProgram.uniformLocation(for: "u_text_progress")
    }
    
    private func compileDirectPassShaders() {
        directPassProgram = ShaderProgram(vertexShaderName: "DirectPassVertex",
                                          fragmentShaderName: "DirectPassFragment")
        directPassPositionSlot = filterProgram.attributeLocation(for: "a_position")
        directPassTexturePositionSlot = filterProgram.attributeLocation(for: "a_texcoord")
        directPassTextureUniform = filterProgram.uniformLocation(for: "u_texture")
    }
    
    private func setupOutputTexture(retainedBufferCountHint: Int) {
        guard let context = context else { return }
        outputTexture = PixelBufferTexture(width: outputWidth, height: outputHeight,
                                           retainedBufferCountHint: retainedBufferCountHint)
        outputTexture.createTextureCache(in: context)
        outputTexture.createBufferPool()
        let testPixelBuffer = outputTexture.createPixelBuffer()
        var outputFormatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                     imageBuffer: testPixelBuffer,
                                                     formatDescriptionOut: &outputFormatDescription)
        self.outputFormatDescription = outputFormatDescription
    }
    
    private func setupRenderDestination() {
        renderDestination = RenderDestination()
        renderDestination.createFrameBuffer()
    }
    
    private func loadTexture(_ filename: String) -> GLuint {
        let path = Bundle.main.path(forResource: filename, ofType: nil)!
        let option = [GLKTextureLoaderOriginBottomLeft: false]
        do {
            let info = try GLKTextureLoader.texture(withContentsOfFile: path, options: option as [String : NSNumber]?)
            return info.name
        } catch {
            DDLogError("Could not load texture \(filename)")
            exit(1)
        }
    }
    
    private func drawText(_ text: String) -> GLuint {
        let textSize = CGSize(width: 200, height: 40)
        let fontSize: CGFloat = 28
        UIGraphicsBeginImageContextWithOptions(.init(width: inputWidth, height: inputHeight), true, 1.0)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        NSString(string: text).draw(in: CGRect(x: (CGFloat(inputWidth) - textSize.width) / 2,
                                               y: CGFloat(inputHeight) - CGFloat(inputHeight - outputHeight) / 2 - textSize.height,
                                               width: textSize.width,
                                               height: fontSize + 2),
                                    withAttributes: [.font: UIFont.boldSystemFont(ofSize: fontSize),
                                                     .foregroundColor: UIColor.green,
                                                     .paragraphStyle: paragraphStyle])
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        if let image = image, let cgImage = image.cgImage {
//            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            let option = [GLKTextureLoaderOriginBottomLeft: false]
            do {
                let info = try GLKTextureLoader.texture(with: cgImage, options: option as [String : NSNumber]?)
                return info.name
            } catch {
                DDLogError("Could not load texture \(text) \(error.localizedDescription)")
                exit(1)
            }
        }
        return 0
    }
    
    private func setupProgress() {
        sequenceIn = Date().addingTimeInterval(2).timeIntervalSince1970
        fadeInEndTime = Date().addingTimeInterval(2 + 3).timeIntervalSince1970
        fadeOutStartTime = Date().addingTimeInterval(2 + 3 + 5).timeIntervalSince1970
        sequenceOut = Date().addingTimeInterval(2 + 3 + 5 + 3).timeIntervalSince1970
    }
    
    private func updateProgress() {
        let currentTime = Date().timeIntervalSince1970
        if currentTime <= fadeInEndTime {
            textProgress = (currentTime - sequenceIn) / (fadeInEndTime - sequenceIn)
        } else if currentTime >= fadeOutStartTime {
            textProgress = 1.0 - (currentTime - fadeOutStartTime) / (sequenceOut - fadeOutStartTime)
        }
        if textProgress < 0 {
            textProgress = 0
        }
        if textProgress > 1 {
            textProgress = 1
        }
    }
    
    private func updateAnimator() {
        animatorCount += 1
        if animatorCount >= animatorStep {
            animatorCount = 0
            animatorIndex += 1
            if animatorIndex >= animatorTextureNames.count {
                animatorIndex = 0
            }
            animatorPositionCurrent = animatorPositionCurrent + animatorProgress
            if animatorPositionCurrent > 1.0 {
                animatorPositionCurrent = animatorPositionOrigin
            }
            let left = animatorPositionCurrent
            let right = left + (animatorWidth / Float(outputWidth)) * 2
            animatorPositionVertices[0] = left
            animatorPositionVertices[2] = right
            animatorPositionVertices[4] = left
            animatorPositionVertices[6] = right
        }
    }
    
    private func reset() {
        let oldContext = EAGLContext.current()
        if context != oldContext {
            if !EAGLContext.setCurrent(context) {
                DDLogError("Could not set current OpenGL context with new context")
                exit(1)
            }
        }
        renderDestination.deleteFrameBuffer()
        filterProgram?.delete()
        directPassProgram?.delete()
        inputTexture?.deleteTextureCache()
        outputTexture?.deleteTextureCache()
        outputTexture?.deleteBufferPool()
        outputFormatDescription = nil
        if oldContext != context {
            if !EAGLContext.setCurrent(oldContext) {
                DDLogError("Could not set current OpenGL context with old context")
                exit(1)
            }
        }
        EAGLContext.setCurrent(nil)
        context = nil
    }
    
}
