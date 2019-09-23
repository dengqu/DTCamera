//
//  OpenGLPreviewView.swift
//  JuYouFan
//
//  Created by Dan Jiang on 2019/9/12.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import UIKit
import GLKit

struct Vertex {
    var x: GLfloat
    var y: GLfloat
    var z: GLfloat
    var r: GLfloat
    var g: GLfloat
    var b: GLfloat
    var a: GLfloat
}

class OpenGLPreviewView: UIView {
    
    var squareVertices: [GLfloat] = [
        -1, -1, // bottom left
        1, -1, // bottom right
        -1, 1, // top left
        1, 1, // top right
    ]

    private var context: EAGLContext?
    private var colorRenderBuffer = GLuint()
    private var frameBuffer = GLuint()
    private var vertextBuffer = GLuint()
    private var positionSlot = GLuint()
    private var texturePositionSlot = GLuint()
    private var textureUniform = GLuint()
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
        compileShaders()
    }
    
    func displayPixelBuffer(_ pixelBuffer: CVPixelBuffer) {
        if frameBuffer == 0 {
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
            print("Could not CVOpenGLESTextureCacheCreateTextureFromImage \(resultCode)")
            exit(1)
        }
        
        glViewport(0, 0, GLint(bounds.size.width), GLint(bounds.size.height))
        
        glClearColor(1, 0, 0, 1.0)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        
        glActiveTexture(GLenum(GL_TEXTURE0))
        glBindTexture(GLenum(GL_TEXTURE_2D), CVOpenGLESTextureGetName(texture))
        glUniform1i(GLint(textureUniform), 0)
        
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
        
        glUniform4f(GLint(colorUniform), 0, 0, 1, 1)
        glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4)

        context?.presentRenderbuffer(Int(GL_RENDERBUFFER))
        
        glBindTexture(GLenum(GL_TEXTURE_2D), 0)
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
        if !EAGLContext.setCurrent(context) {
            print("Could not set current OpenGL context")
            exit(1)
        }
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
            print("Could not CVOpenGLESTextureCacheCreate %d", resultCode)
            exit(1)
        }
    }
    
    private func compileShaders() {
        let vertexShader = compileShader(name: "SimpleVertex", with: GLenum(GL_VERTEX_SHADER))
        let fragmentShader = compileShader(name: "SimpleFragment", with: GLenum(GL_FRAGMENT_SHADER))
        
        let program = glCreateProgram()
        glAttachShader(program, vertexShader)
        glAttachShader(program, fragmentShader)
        glLinkProgram(program)
        
        var linkStatus = GLint()
        glGetProgramiv(program, GLenum(GL_LINK_STATUS), &linkStatus)
        if linkStatus == GL_FALSE {
            let bufferLength: GLsizei = 1024
            let info: [GLchar] = Array(repeating: GLchar(0), count: Int(bufferLength))
            glGetProgramInfoLog(program, bufferLength, nil, UnsafeMutablePointer(mutating: info))
            print(String(validatingUTF8: info) ?? "")
            exit(1)
        }
        
        glUseProgram(program)
        
        positionSlot = GLuint(glGetAttribLocation(program, "a_position"))
        texturePositionSlot = GLuint(glGetAttribLocation(program, "a_texcoord"))
        textureUniform = GLuint(glGetUniformLocation(program, "u_texture"))
        colorUniform = GLuint(glGetUniformLocation(program, "u_color"))
    }
    
    private func compileShader(name: String, with type: GLenum) -> GLuint {
        do {
            guard let shaderPath = Bundle.main.path(forResource: name, ofType: "glsl") else {
                print("Could not find shader file \(name)")
                exit(1)
            }
            let shaderString = try NSString(contentsOfFile: shaderPath, encoding: String.Encoding.utf8.rawValue)
            var shaderCString = shaderString.utf8String
            var shaderStringLength = GLint(shaderString.length)
            let shader = glCreateShader(type)
            glShaderSource(shader, 1, &shaderCString, &shaderStringLength)
            
            glCompileShader(shader)
            
            var compileStatus = GLint()
            glGetShaderiv(shader, GLenum(GL_COMPILE_STATUS), &compileStatus)
            
            if compileStatus == GL_FALSE {
                let bufferLength: GLsizei = 1024
                let info: [GLchar] = Array(repeating: GLchar(0), count: Int(bufferLength))
                glGetShaderInfoLog(shader, bufferLength, nil, UnsafeMutablePointer(mutating: info))
                print(String(validatingUTF8: info) ?? "")
                exit(1)
            }
            
            return shader
        } catch {
            print("Could not load shader file \(name)")
            exit(1)
        }
    }
    
}
