//
//  OpenGLPreviewView.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/9/12.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import UIKit
import GLKit

class OpenGLPreviewView: UIView {
    
    var squareVertices: [GLfloat] = [
        -1, -1, // bottom left
        1, -1, // bottom right
        -1, 1, // top left
        1, 1, // top right
    ]

    private var context: EAGLContext?
    
    private var program: ShaderProgram!
    
    private var colorRenderBuffer = GLuint()
    private var frameBuffer = GLuint()
    
    private var positionSlot = GLuint()
    private var texturePositionSlot = GLuint()
    private var textureUniform = GLint()
    private var colorUniform = GLuint()

    private var textureCache: CVOpenGLESTextureCache!

    override class var layerClass: AnyClass {
        return CAEAGLLayer.self
    }

    private var eaglLayer: CAEAGLLayer? {
        return layer as? CAEAGLLayer
    }
    
    deinit {
        EAGLContext.setCurrent(nil)
        
        context = nil
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        
        setupLayer()
        setupContext()
    }
    
    func displayPixelBuffer(_ pixelBuffer: CVPixelBuffer) {
        let oldContext = EAGLContext.current()
        if context != oldContext {
            if !EAGLContext.setCurrent(context) {
                print("Could not set current OpenGL context with new context")
                exit(1)
            }
        }

        if frameBuffer == 0 {
            compileShaders()
            setupBuffers()
        }
        
        let frameWidth = CVPixelBufferGetWidth(pixelBuffer)
        let frameHeight = CVPixelBufferGetHeight(pixelBuffer)
        var texture: CVOpenGLESTexture!
        let resultCode = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                                      textureCache,
                                                                      pixelBuffer,
                                                                      nil,
                                                                      GLenum(GL_TEXTURE_2D),
                                                                      GL_RGBA,
                                                                      GLsizei(frameWidth),
                                                                      GLsizei(frameHeight),
                                                                      GLenum(GL_BGRA),
                                                                      GLenum(GL_UNSIGNED_BYTE),
                                                                      0,
                                                                      &texture)
        if resultCode != kCVReturnSuccess {
            print("Could not create texture from image \(resultCode)")
            exit(1)
        }
        
        glViewport(0, 0, GLint(bounds.size.width), GLint(bounds.size.height))
        
        glClearColor(0.85, 0.85, 0.85, 1.0)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        
        program.use()

        glActiveTexture(GLenum(GL_TEXTURE0))
        glBindTexture(GLenum(GL_TEXTURE_2D), CVOpenGLESTextureGetName(texture))
        glUniform1i(textureUniform, 0)
        
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

        // Preserve aspect ratio; fill layer bounds
        var textureSamplingSize: CGSize = .zero
        let cropScaleAmount = CGSize(width: bounds.size.width / CGFloat(frameWidth),
                                     height: bounds.size.height / CGFloat(frameHeight))
        if cropScaleAmount.height > cropScaleAmount.width {
            textureSamplingSize.width = bounds.size.width / CGFloat(frameWidth) * cropScaleAmount.height
            textureSamplingSize.height = 1.0;
        }
        else {
            textureSamplingSize.width = 1.0;
            textureSamplingSize.height = bounds.size.height / CGFloat(frameHeight) * cropScaleAmount.width;
        }
        
        // Perform a vertical flip by swapping the top left and the bottom left coordinate.
        // CVPixelBuffers have a top left origin and OpenGL has a bottom left origin.
        var passThroughTextureVertices: [GLfloat] = [
            (1.0 - GLfloat(textureSamplingSize.width)) / 2.0, (1.0 + GLfloat(textureSamplingSize.height)) / 2.0, // top left
            (1.0 + GLfloat(textureSamplingSize.width)) / 2.0, (1.0 + GLfloat(textureSamplingSize.height)) / 2.0, // top right
            (1.0 - GLfloat(textureSamplingSize.width)) / 2.0, (1.0 - GLfloat(textureSamplingSize.height)) / 2.0, // bottom left
            (1.0 + GLfloat(textureSamplingSize.width)) / 2.0, (1.0 - GLfloat(textureSamplingSize.height)) / 2.0, // bottom right
        ]
        
        glEnableVertexAttribArray(texturePositionSlot)
        glVertexAttribPointer(texturePositionSlot,
                              2,
                              GLenum(GL_FLOAT),
                              GLboolean(UInt8(GL_FALSE)),
                              GLsizei(0),
                              &passThroughTextureVertices)
        
        glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4)

        context?.presentRenderbuffer(Int(GL_RENDERBUFFER))
        
        glBindTexture(GLenum(GL_TEXTURE_2D), 0)
        
        if oldContext != context {
            if !EAGLContext.setCurrent(oldContext) {
                print("Could not set current OpenGL context with old context")
                exit(1)
            }
        }
    }
    
    private func setupLayer() {
        guard let eaglLayer = eaglLayer else { return }
        
        eaglLayer.isOpaque = true
        eaglLayer.drawableProperties = [kEAGLDrawablePropertyRetainedBacking: false,
                                        kEAGLDrawablePropertyColorFormat: kEAGLColorFormatRGBA8]
    }
    
    private func setupContext() {
        guard let context = EAGLContext(api: .openGLES2) else {
            print("Could not initialize OpenGL context")
            exit(1)
        }
        self.context = context
    }
    
    private func compileShaders() {
        program = ShaderProgram(vertexShaderName: "PreviewVertex", fragmentShaderName: "PreviewFragment")
        positionSlot = program.attributeLocation(for: "a_position")
        texturePositionSlot = program.attributeLocation(for: "a_texcoord")
        textureUniform = program.uniformLocation(for: "u_texture")
    }
    
    private func setupBuffers() {
        guard let context = context, let eaglLayer = eaglLayer else { return }
        
        glGenFramebuffers(1, &frameBuffer)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), frameBuffer)

        glGenRenderbuffers(1, &colorRenderBuffer)
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), colorRenderBuffer)
        
        if !context.renderbufferStorage(Int(GL_RENDERBUFFER), from: eaglLayer) {
            print("Could not bind a drawable object’s storage to a render buffer object")
            exit(1)
        }

        glFramebufferRenderbuffer(GLenum(GL_FRAMEBUFFER),
                                  GLenum(GL_COLOR_ATTACHMENT0),
                                  GLenum(GL_RENDERBUFFER),
                                  colorRenderBuffer)
        if glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER)) != GL_FRAMEBUFFER_COMPLETE {
            print("Could not generate frame buffer")
            exit(1)
        }
        
        let resultCode = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, nil, context, nil, &textureCache)
        if resultCode != kCVReturnSuccess {
            print("Could not create texture cache \(resultCode)")
            exit(1)
        }
    }
    
}
