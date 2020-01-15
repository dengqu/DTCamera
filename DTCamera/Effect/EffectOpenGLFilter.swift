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

    private var logoOffset: GLfloat = 0.05
    private var logoSize: GLfloat = 0.2
    private var logoPositionVertices: [GLfloat] = [ // vertical flip
        -1, -1, // top left
        1, -1, // top right
        -1, 1, // bottom left
        1, 1, // bottom right
    ]
    private var logoTextureVertices: [Float] = [
        0, 0, // bottom left
        1, 0, // bottom right
        0, 1, // top left
        1, 1, // top right
    ]
    private var logoTextureName = GLuint()
    
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
        }
        if directPassProgram == nil {
            compileDirectPassShaders()
            logoTextureName = loadTexture("logo.png")
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

        // draw camera texture
        
        filterProgram.use()
        
        inputTexture.createTexture(from: pixelBuffer)
        inputTexture.bind(textureNo: GLenum(GL_TEXTURE1))
        glUniform1i(filterTextureUniform, 1)
        
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
                              &logoTextureVertices)
        
        glActiveTexture(GLenum(GL_TEXTURE1))
        glBindTexture(GLenum(GL_TEXTURE_2D), logoTextureName)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
        glUniform1i(directPassTextureUniform, 1)

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
        
        let scale = GLfloat(targetWidth / targetHeight)
        // top left
        logoPositionVertices[0] = -1 + logoOffset
        logoPositionVertices[1] = 1 - (logoOffset + logoSize) * scale
        // top right
        logoPositionVertices[2] = -1 + (logoOffset + logoSize)
        logoPositionVertices[3] = 1 - (logoOffset + logoSize) * scale
        // bottom left
        logoPositionVertices[4] = -1 + logoOffset
        logoPositionVertices[5] = 1 - logoOffset * scale
        // bottom right
        logoPositionVertices[6] = -1 + (logoOffset + logoSize)
        logoPositionVertices[7] = 1 - logoOffset * scale

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
        filterProgram = ShaderProgram(vertexShaderName: "RemoveGreenFilterVertex",
                                      fragmentShaderName: "RemoveGreenFilterFragment")
        filterPositionSlot = filterProgram.attributeLocation(for: "a_position")
        filterTexturePositionSlot = filterProgram.attributeLocation(for: "a_texcoord")
        filterTextureUniform = filterProgram.uniformLocation(for: "u_texture")
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
