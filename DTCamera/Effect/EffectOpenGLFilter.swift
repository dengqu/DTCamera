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
    private var program: ShaderProgram!
    private var positionSlot = GLuint()
    private var texturePositionSlot = GLuint()
    private var textureUniform = GLint()

    // Output
    private var outputWidth: Int = 0
    private var outputHeight: Int = 0
    private var outputTexture: PixelBufferTexture!
    private let renderDestination = RenderDestination()

    deinit {
        reset()
    }

    init() {
        guard let context = EAGLContext(api: .openGLES2) else {
            print("Could not initialize OpenGL context")
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
                print("Could not set current OpenGL context with new context")
                exit(1)
            }
        }
        
        setupInput()
        compileShaders()
        setupOutput(retainedBufferCountHint: retainedBufferCountHint)
        
        if oldContext !== context {
            if !EAGLContext.setCurrent(oldContext) {
                print("Could not set current OpenGL context with old context")
                exit(1)
            }
        }
    }

    func filter(pixelBuffer: CVPixelBuffer) -> CVPixelBuffer {
        let oldContext = EAGLContext.current()
        if context !== oldContext {
            if !EAGLContext.setCurrent(context) {
                print("Could not set current OpenGL context with new context")
                exit(1)
            }
        }

        program.use()
        
        inputTexture.createTexture(from: pixelBuffer)
        inputTexture.bind(textureNo: GLenum(GL_TEXTURE1))
        glUniform1i(textureUniform, 1)
        
        let outputPixelBuffer = outputTexture.createTexture()
        outputTexture.bind(textureNo: GLenum(GL_TEXTURE0))
        renderDestination.attachTexture(name: outputTexture.textureName)
        
        glEnableVertexAttribArray(positionSlot)
        glVertexAttribPointer(positionSlot,
                              2,
                              GLenum(GL_FLOAT),
                              GLboolean(UInt8(GL_FALSE)),
                              GLsizei(0),
                              &squareVertices)
        
        glEnableVertexAttribArray(texturePositionSlot)
        glVertexAttribPointer(texturePositionSlot,
                              2,
                              GLenum(GL_FLOAT),
                              GLboolean(UInt8(GL_FALSE)),
                              GLsizei(0),
                              &textureVertices)
        
        glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4)
        
        glFlush()
        
        inputTexture.unbind()
        outputTexture.unbind()
        inputTexture.deleteTexture()
        outputTexture.deleteTexture()

        if oldContext !== context {
            if !EAGLContext.setCurrent(oldContext) {
                print("Could not set current OpenGL context with old context")
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
        if positionMode == .front {
            let fromX: Float = 0.0
            let toX: Float = 1.0
            textureVertices[0] = toX
            textureVertices[2] = fromX
            textureVertices[4] = toX
            textureVertices[6] = fromX
        }
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
    
    private func compileShaders() {
        program = ShaderProgram(vertexShaderName: "DumbFilterVertex", fragmentShaderName: "DumbFilterFragment")
        positionSlot = program.attributeLocation(for: "a_position")
        texturePositionSlot = program.attributeLocation(for: "a_texcoord")
        textureUniform = program.uniformLocation(for: "u_texture")
    }
    
    private func setupOutput(retainedBufferCountHint: Int) {
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
        renderDestination.createFrameBuffer(width: outputWidth, height: outputHeight)
    }
    
    private func reset() {
        let oldContext = EAGLContext.current()
        if context != oldContext {
            if !EAGLContext.setCurrent(context) {
                print("Could not set current OpenGL context with new context")
                exit(1)
            }
        }
        renderDestination.deleteFrameBuffer()
        program.delete()
        inputTexture.deleteTextureCache()
        outputTexture.deleteTextureCache()
        outputTexture.deleteBufferPool()
        outputFormatDescription = nil
        if oldContext != context {
            if !EAGLContext.setCurrent(oldContext) {
                print("Could not set current OpenGL context with old context")
                exit(1)
            }
        }
        EAGLContext.setCurrent(nil)
        context = nil
    }
    
}
