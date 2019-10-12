//
//  EffectOpenGLRender.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/9/27.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import UIKit
import GLKit
import CoreMedia

class EffectOpenGLRender: EffectRender {
    
    var squareVertices: [GLfloat] = [
        -1, -1, // bottom left
        1, -1, // bottom right
        -1, 1, // top left
        1, 1, // top right
    ]

    var textureVertices: [Float] = [
        0, 0, // bottom left
        1, 0, // bottom right
        0, 1, // top left
        1, 1, // top right
    ]

    private var context: EAGLContext?

    private var program: ShaderProgram!

    private var frameBuffer = GLuint()

    private var positionSlot = GLuint()
    private var texturePositionSlot = GLuint()
    private var textureUniform = GLint()

    private var inputTextureCache: CVOpenGLESTextureCache!
    private var outputTextureCache: CVOpenGLESTextureCache!
    private var bufferPool: CVPixelBufferPool!
    private var bufferPoolAuxAttributes: NSDictionary!

    init() {
        setupContext()
    }
    
    func prepareForInput(with formatDescription: CMFormatDescription, outputRetainedBufferCountHint: Int) {
        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)

        let oldContext = EAGLContext.current()
        if context !== oldContext {
            if !EAGLContext.setCurrent(context) {
                print("Could not set current OpenGL context with new context")
                exit(1)
            }
        }
        
        setupBuffers(with: dimensions, retainedBufferCountHint: outputRetainedBufferCountHint)
        
        if oldContext !== context {
            if !EAGLContext.setCurrent(oldContext) {
                print("Could not set current OpenGL context with old context")
                exit(1)
            }
        }
    }

    func copyRenderedPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer {
        let oldContext = EAGLContext.current()
        if context !== oldContext {
            if !EAGLContext.setCurrent(context) {
                print("Could not set current OpenGL context with new context")
                exit(1)
            }
        }

        let frameWidth = CVPixelBufferGetWidth(pixelBuffer)
        let frameHeight = CVPixelBufferGetHeight(pixelBuffer)
        var inputTexture: CVOpenGLESTexture!
        var resultCode = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                                      inputTextureCache,
                                                                      pixelBuffer,
                                                                      nil,
                                                                      GLenum(GL_TEXTURE_2D),
                                                                      GL_RGBA,
                                                                      GLsizei(frameWidth),
                                                                      GLsizei(frameHeight),
                                                                      GLenum(GL_BGRA),
                                                                      GLenum(GL_UNSIGNED_BYTE),
                                                                      0,
                                                                      &inputTexture)
        if inputTexture == nil || resultCode != kCVReturnSuccess {
            print("Could not create input texture from image \(resultCode)")
            exit(1)
        }
        
        var outputTexture: CVOpenGLESTexture!
        var outputPixelBuffer: CVPixelBuffer!
        resultCode = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault,
                                                                         bufferPool,
                                                                         bufferPoolAuxAttributes,
                                                                         &outputPixelBuffer)
        if resultCode == kCVReturnWouldExceedAllocationThreshold {
            CVOpenGLESTextureCacheFlush(outputTextureCache, 0)
            resultCode = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault,
                                                                             bufferPool,
                                                                             bufferPoolAuxAttributes,
                                                                             &outputPixelBuffer)
        }
        if resultCode != kCVReturnSuccess {
            if resultCode == kCVReturnWouldExceedAllocationThreshold {
                print("Pool is out of buffers, dropping frame \(resultCode)")
            } else {
                print("Could not create pixel buffer in pool \(resultCode)")
            }
            exit(1)
        }
            
        resultCode = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                                  outputTextureCache,
                                                                  outputPixelBuffer,
                                                                  nil,
                                                                  GLenum(GL_TEXTURE_2D),
                                                                  GL_RGBA,
                                                                  GLsizei(frameWidth),
                                                                  GLsizei(frameHeight),
                                                                  GLenum(GL_BGRA),
                                                                  GLenum(GL_UNSIGNED_BYTE),
                                                                  0,
                                                                  &outputTexture)
        if outputTexture == nil || resultCode != kCVReturnSuccess {
            print("Could not create output texture from image \(resultCode)")
            exit(1)
        }
        
        glViewport(0, 0, GLint(frameWidth), GLint(frameHeight))
               
        glClearColor(0.85, 0.85, 0.85, 1.0)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))

        program.use()
        
        // Set up our output pixel buffer as the framebuffer's render target.
        glActiveTexture(GLenum(GL_TEXTURE0))
        glBindTexture(CVOpenGLESTextureGetTarget(outputTexture), CVOpenGLESTextureGetName(outputTexture))
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
        glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER),
                               GLenum(GL_COLOR_ATTACHMENT0),
                               CVOpenGLESTextureGetTarget(outputTexture),
                               CVOpenGLESTextureGetName(outputTexture),
                               0)
        
        // Render our source pixel buffer.
        glActiveTexture(GLenum(GL_TEXTURE1))
        glBindTexture(CVOpenGLESTextureGetTarget(inputTexture), CVOpenGLESTextureGetName(inputTexture))
        glUniform1i(textureUniform, 1)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)

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
        
        glBindTexture(CVOpenGLESTextureGetTarget(inputTexture), 0)
        glBindTexture(CVOpenGLESTextureGetTarget(outputTexture), 0)
        
        glFlush()

        if oldContext !== context {
            if !EAGLContext.setCurrent(oldContext) {
                print("Could not set current OpenGL context with old context")
                exit(1)
            }
        }
        
        return outputPixelBuffer
    }
    
    private func setupContext() {
        guard let context = EAGLContext(api: .openGLES2) else {
            print("Could not initialize OpenGL context")
            exit(1)
        }
        self.context = context
    }
    
    private func compileShaders() {
        program = ShaderProgram(vertexShaderName: "DumbFilterVertex", fragmentShaderName: "DumbFilterFragment")
        positionSlot = program.attributeLocation(for: "a_position")
        texturePositionSlot = program.attributeLocation(for: "a_texcoord")
        textureUniform = program.uniformLocation(for: "u_texture")
    }
    
    private func setupBuffers(with outputDimensions: CMVideoDimensions, retainedBufferCountHint: Int) {
        guard let context = context else { return }
        
        glDisable(GLenum(GL_DEPTH_TEST))
        
        glGenFramebuffers(1, &frameBuffer)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), frameBuffer)
        
        var resultCode = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, nil, context, nil, &inputTextureCache)
        if resultCode != kCVReturnSuccess {
            print("Could not create input texture cache \(resultCode)")
            exit(1)
        }
        
        resultCode = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, nil, context, nil, &outputTextureCache)
        if resultCode != kCVReturnSuccess {
            print("Could not create output texture cache \(resultCode)")
            exit(1)
        }
        
        compileShaders()
        
        let pixelBufferPoolOptions: NSDictionary = [kCVPixelBufferPoolMinimumBufferCountKey: retainedBufferCountHint]
        let sourcePixelBufferOptions: NSDictionary = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                                                      kCVPixelBufferWidthKey: outputDimensions.width,
                                                      kCVPixelBufferHeightKey: outputDimensions.height,
                                                      kCVPixelFormatOpenGLESCompatibility: true,
                                                      kCVPixelBufferIOSurfacePropertiesKey: NSDictionary()]
        resultCode = CVPixelBufferPoolCreate(kCFAllocatorDefault,
                                             pixelBufferPoolOptions,
                                             sourcePixelBufferOptions,
                                             &bufferPool)
        if resultCode != kCVReturnSuccess {
            print("Could not create pixel buffer pool \(resultCode)")
            exit(1)
        }
        
        bufferPoolAuxAttributes = [kCVPixelBufferPoolAllocationThresholdKey: retainedBufferCountHint]
        preallocatePixelBuffers(in: bufferPool, auxAttributes: bufferPoolAuxAttributes)
    }
    
    private func preallocatePixelBuffers(in pool: CVPixelBufferPool, auxAttributes: NSDictionary) {
        var pixelBuffers: [CVPixelBuffer] = []
        while true {
            var pixelBuffer: CVPixelBuffer!
            let resultCode = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault,
                                                                                 pool,
                                                                                 auxAttributes,
                                                                                 &pixelBuffer)
            if resultCode == kCVReturnWouldExceedAllocationThreshold {
                break
            }
            pixelBuffers.append(pixelBuffer)
        }
        pixelBuffers.removeAll()
    }
    
    private func loadTexture(_ filename: String) -> GLuint {
        guard let path = Bundle.main.path(forResource: filename, ofType: nil) else {
            return 0
        }
        let option = [GLKTextureLoaderOriginBottomLeft: true]
        do {
            let info = try GLKTextureLoader.texture(withContentsOfFile: path, options: option as [String : NSNumber]?)
            return info.name
        } catch {
            return 0
        }
    }
    
}
