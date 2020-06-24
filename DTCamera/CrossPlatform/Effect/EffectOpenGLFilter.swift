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

struct Particle {
    var pID: GLfloat = 0
    var pRadiusOffset: GLfloat = 0
    var pVelocityOffset: GLfloat = 0
    var pDecayOffset: GLfloat = 0
    var pSizeOffset: GLfloat = 0
    var pColorOffsetR: GLfloat = 0
    var pColorOffsetG: GLfloat = 0
    var pColorOffsetB: GLfloat = 0
}

class Emitter {
    var eParticles: [Particle] = []
    var eRadius: GLfloat = 0
    var eVelocity: GLfloat = 0
    var eDecay: GLfloat = 0
    var eSizeStart: GLfloat = 0
    var eSizeEnd: GLfloat = 0
    var eColorStart: GLKVector3 = GLKVector3Make(0, 0, 0)
    var eColorEnd: GLKVector3 = GLKVector3Make(0, 0, 0)
    var ePosition: GLKVector2 = GLKVector2Make(0, 0)
}

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
    
    private let numberOfParticles = 180
    private var gravity = GLKVector2Make(0, 0)
    private var life: Float = 0
    private var time: Float = 0
    private var particleBuffer = GLuint()
    private var emitter: Emitter?
    
    private var emitterProgram: ShaderProgram!
    private var emitter_a_pID = GLuint()
    private var emitter_a_pRadiusOffset = GLuint()
    private var emitter_a_pVelocityOffset = GLuint()
    private var emitter_a_pDecayOffset = GLuint()
    private var emitter_a_pSizeOffset = GLuint()
    private var emitter_a_pColorOffset = GLuint()
    private var emitter_u_ProjectionMatrix = GLint()
    private var emitter_u_Gravity = GLint()
    private var emitter_u_Time = GLint()
    private var emitter_u_eRadius = GLint()
    private var emitter_u_eVelocity = GLint()
    private var emitter_u_eDecay = GLint()
    private var emitter_u_eSizeStart = GLint()
    private var emitter_u_eSizeEnd = GLint()
    private var emitter_u_eColorStart = GLint()
    private var emitter_u_eColorEnd = GLint()
    private var emitter_u_Texture = GLint()
    private var emitter_u_ePosition = GLint()
    private var emitterTextureName = GLuint()
    private var isFlower = true
    private var explosionTextureName = GLuint()
    private var flowerTextureName = GLuint()

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
        if emitterProgram == nil {
            compileEmitterShaders()
            explosionTextureName = loadTexture("explosion.png")
            flowerTextureName = loadTexture("flower.png")
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
        
        // draw particle system
        
        if let emitter = emitter {
            updateEmitter()
            
            emitterProgram.use()
            
            glGenBuffers(1, &particleBuffer)
            glBindBuffer(GLenum(GL_ARRAY_BUFFER), particleBuffer)
            glBufferData(GLenum(GL_ARRAY_BUFFER), MemoryLayout<Particle>.size * numberOfParticles, emitter.eParticles, GLenum(GL_STATIC_DRAW))
            
            let aspectRatio = Float(outputWidth) / Float(outputHeight)
            let projectionMatrix = GLKMatrix4MakeScale(1.0, aspectRatio, 1.0)
            
            glUniformMatrix4fv(emitter_u_ProjectionMatrix, 1, 0, projectionMatrix.array)
            glUniform2f(emitter_u_Gravity, gravity.x, gravity.y)
            glUniform1f(emitter_u_Time, time)
            glUniform1f(emitter_u_eRadius, emitter.eRadius)
            glUniform1f(emitter_u_eVelocity, emitter.eVelocity)
            glUniform1f(emitter_u_eDecay, emitter.eDecay)
            glUniform1f(emitter_u_eSizeStart, emitter.eSizeStart)
            glUniform1f(emitter_u_eSizeEnd, emitter.eSizeEnd)
            glUniform3f(emitter_u_eColorStart, emitter.eColorStart.r, emitter.eColorStart.g, emitter.eColorStart.b)
            glUniform3f(emitter_u_eColorEnd, emitter.eColorEnd.r, emitter.eColorEnd.g, emitter.eColorEnd.b)
            glUniform2f(emitter_u_ePosition, emitter.ePosition.x, emitter.ePosition.y)
            
            glActiveTexture(GLenum(GL_TEXTURE0))
            glBindTexture(GLenum(GL_TEXTURE_2D), emitterTextureName)
            glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
            glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
            glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
            glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
            glUniform1i(emitter_u_Texture, 0)
            
            glEnableVertexAttribArray(emitter_a_pID)
            glEnableVertexAttribArray(emitter_a_pRadiusOffset)
            glEnableVertexAttribArray(emitter_a_pVelocityOffset)
            glEnableVertexAttribArray(emitter_a_pDecayOffset)
            glEnableVertexAttribArray(emitter_a_pColorOffset)
            
            glVertexAttribPointer(emitter_a_pID, 1, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(MemoryLayout<Particle>.size), BUFFER_OFFSET(0))
            glVertexAttribPointer(emitter_a_pRadiusOffset, 1, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(MemoryLayout<Particle>.size), BUFFER_OFFSET(MemoryLayout<GLfloat>.size))
            glVertexAttribPointer(emitter_a_pVelocityOffset, 1, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(MemoryLayout<Particle>.size), BUFFER_OFFSET(2 * MemoryLayout<GLfloat>.size))
            glVertexAttribPointer(emitter_a_pDecayOffset, 1, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(MemoryLayout<Particle>.size), BUFFER_OFFSET(3 * MemoryLayout<GLfloat>.size))
            glVertexAttribPointer(emitter_a_pSizeOffset, 1, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(MemoryLayout<Particle>.size), BUFFER_OFFSET(4 * MemoryLayout<GLfloat>.size))
            glVertexAttribPointer(emitter_a_pColorOffset, 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(MemoryLayout<Particle>.size), BUFFER_OFFSET(5 * MemoryLayout<GLfloat>.size))
            
            glDrawArrays(GLenum(GL_POINTS), 0, GLsizei(numberOfParticles));
            
            glDisableVertexAttribArray(emitter_a_pID);
            glDisableVertexAttribArray(emitter_a_pRadiusOffset);
            glDisableVertexAttribArray(emitter_a_pVelocityOffset);
            glDisableVertexAttribArray(emitter_a_pDecayOffset);
            glDisableVertexAttribArray(emitter_a_pSizeOffset);
            glDisableVertexAttribArray(emitter_a_pColorOffset);
            
            glBindBuffer(GLenum(GL_ARRAY_BUFFER), 0)
        }
        
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
    
    func addEmitter(x: CGFloat, y: CGFloat) {
        if emitter == nil {
            loadParticleSystem(position: GLKVector2Make(Float(x), Float(-y)))
            emitterTextureName = isFlower ? flowerTextureName : explosionTextureName
            isFlower = !isFlower
        }
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
    
    private func compileEmitterShaders() {
        emitterProgram = ShaderProgram(vertexShaderName: "EmitterVertex",
                                       fragmentShaderName: "EmitterFragment")
        emitter_a_pID = emitterProgram.attributeLocation(for: "a_pID")
        emitter_a_pRadiusOffset = emitterProgram.attributeLocation(for: "a_pRadiusOffset")
        emitter_a_pVelocityOffset = emitterProgram.attributeLocation(for: "a_pVelocityOffset")
        emitter_a_pDecayOffset = emitterProgram.attributeLocation(for: "a_pDecayOffset")
        emitter_a_pSizeOffset = emitterProgram.attributeLocation(for: "a_pSizeOffset")
        emitter_a_pColorOffset = emitterProgram.attributeLocation(for: "a_pColorOffset")
        emitter_u_ProjectionMatrix = emitterProgram.uniformLocation(for: "u_ProjectionMatrix")
        emitter_u_Gravity = emitterProgram.uniformLocation(for: "u_Gravity")
        emitter_u_Time = emitterProgram.uniformLocation(for: "u_Time")
        emitter_u_eRadius = emitterProgram.uniformLocation(for: "u_eRadius")
        emitter_u_eVelocity = emitterProgram.uniformLocation(for: "u_eVelocity")
        emitter_u_eDecay = emitterProgram.uniformLocation(for: "u_eDecay")
        emitter_u_eSizeStart = emitterProgram.uniformLocation(for: "u_eSizeStart")
        emitter_u_eSizeEnd = emitterProgram.uniformLocation(for: "u_eSizeEnd")
        emitter_u_eColorStart = emitterProgram.uniformLocation(for: "u_eColorStart")
        emitter_u_eColorEnd = emitterProgram.uniformLocation(for: "u_eColorEnd")
        emitter_u_Texture = emitterProgram.uniformLocation(for: "u_Texture")
        emitter_u_ePosition = emitterProgram.uniformLocation(for: "u_ePosition")
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
    
    private func updateEmitter() {
        time += 0.033
        if time >= life {
            emitter = nil
            time = 0
        }
    }
        
    func loadParticleSystem(position: GLKVector2) {
        let newEmitter = Emitter()
        
        let oRadius: Float = 0.10
        let oVelocity: Float = 0.50
        let oDecay: Float = 0.25
        let oSize: Float = 8.00
        let oColor: Float = 0.25

        for i in 0..<numberOfParticles {
            var particle = Particle()
            particle.pID = GLKMathDegreesToRadians(Float(i) / Float(numberOfParticles) * 360.0)
            particle.pRadiusOffset = randomFloatBetween(min: oRadius, max: 1.00)
            particle.pVelocityOffset = randomFloatBetween(min: -oVelocity, max: oVelocity)
            particle.pDecayOffset = randomFloatBetween(min: -oDecay, max: oDecay)
            particle.pSizeOffset = randomFloatBetween(min: -oSize, max: oSize)
            particle.pColorOffsetR = randomFloatBetween(min: -oColor, max: oColor)
            particle.pColorOffsetG = randomFloatBetween(min: -oColor, max: oColor)
            particle.pColorOffsetB = randomFloatBetween(min: -oColor, max: oColor)
            newEmitter.eParticles.append(particle)
        }
        
        newEmitter.eRadius = 0.75
        newEmitter.eVelocity = 3.00
        newEmitter.eDecay = 2.00
        newEmitter.eSizeStart = 32.00
        newEmitter.eColorStart = GLKVector3Make(1.00, 0.50, 0.00)
        newEmitter.eSizeEnd = 8.00
        newEmitter.eColorEnd = GLKVector3Make(0.25, 0.00, 0.00)
        newEmitter.ePosition = position
        
        let growth = newEmitter.eRadius / newEmitter.eVelocity
        life = growth + newEmitter.eDecay + oDecay
        
        let drag: Float = -10.00 // before vertical flip
        gravity = GLKVector2Make(0.00, -9.81 * (1.0 / drag))

        emitter = newEmitter
    }

    private func randomFloatBetween(min: Float, max: Float) -> Float {
        let range = max - min
        return Float(arc4random() % (UInt32(RAND_MAX) + 1)) / Float(RAND_MAX) * range + min
    }
    
    private func BUFFER_OFFSET(_ n: Int) -> UnsafeRawPointer? {
        return UnsafeRawPointer(bitPattern: n)
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
