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
    
    var Vertices = [
        Vertex(x:  1, y: -1, z: 0, r: 1, g: 0, b: 0, a: 1),
        Vertex(x:  1, y:  1, z: 0, r: 0, g: 1, b: 0, a: 1),
        Vertex(x: -1, y:  1, z: 0, r: 0, g: 0, b: 1, a: 1),
        Vertex(x: -1, y: -1, z: 0, r: 0, g: 0, b: 0, a: 1),
    ]
    
    var Indices: [GLubyte] = [
        0, 1, 2,
        2, 3, 0
    ]
    
    private var context: EAGLContext?
    private var colorRenderBuffer = GLuint()
    private var frameBuffer = GLuint()
    private var positionSlot = GLuint()
    private var colorSlot = GLuint()
    private var vao = GLuint()
    private var vertextBuffer = GLuint()
    private var indexBuffer = GLuint()

    override class var layerClass: AnyClass {
        return CAEAGLLayer.self
    }

    private var eaglLayer: CAEAGLLayer? {
        return layer as? CAEAGLLayer
    }
    
    deinit {
        EAGLContext.setCurrent(context)
        
        glDeleteBuffers(1, &vao)
        glDeleteBuffers(1, &vertextBuffer)
        glDeleteBuffers(1, &indexBuffer)
        
        EAGLContext.setCurrent(nil)
        
        context = nil
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = UIColor.blue
        
        setupLayer()
        setupContext()
        compileShaders()
        setupBuffers()
    }
    
    func displayPixelBuffer(_ pixelBuffer: CVPixelBuffer) {
            
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
    
    private func setupFrameBuffer() {
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
        
        positionSlot = GLuint(glGetAttribLocation(program, "a_Position"))
        colorSlot = GLuint(glGetAttribLocation(program, "a_Color"))
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
    
    private func setupBuffers() {
        let vertexSize = MemoryLayout<Vertex>.stride
        let colorOffset = MemoryLayout<GLfloat>.stride * 3
        let colorOffsetPointer = UnsafeRawPointer(bitPattern: colorOffset)
        
        glGenVertexArraysOES(1, &vao)
        glBindVertexArrayOES(vao)
        
        glGenBuffers(1, &vertextBuffer)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), vertextBuffer)
        glBufferData(GLenum(GL_ARRAY_BUFFER),
                     Vertices.size(),
                     Vertices,
                     GLenum(GL_STATIC_DRAW))
        
        glEnableVertexAttribArray(positionSlot)
        glVertexAttribPointer(positionSlot,
                              3,
                              GLenum(GL_FLOAT),
                              GLboolean(UInt8(GL_FALSE)),
                              GLsizei(vertexSize),
                              nil)
        glEnableVertexAttribArray(colorSlot)
        glVertexAttribPointer(colorSlot,
                              4,
                              GLenum(GL_FLOAT),
                              GLboolean(UInt8(GL_FALSE)),
                              GLsizei(vertexSize),
                              colorOffsetPointer)
        
        glGenBuffers(1, &indexBuffer)
        glBindBuffer(GLenum(GL_ELEMENT_ARRAY_BUFFER), indexBuffer)
        glBufferData(GLenum(GL_ELEMENT_ARRAY_BUFFER),
                     Indices.size(),
                     Indices,
                     GLenum(GL_STATIC_DRAW))
        
        glBindVertexArrayOES(0)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), 0)
        glBindBuffer(GLenum(GL_ELEMENT_ARRAY_BUFFER), 0)
    }
    
    func drawFrame() {
        if frameBuffer == 0 {
            setupFrameBuffer()
        }
        
        glViewport(0, 0, GLint(bounds.size.width), GLint(bounds.size.height))
        
        glClearColor(1, 0, 0, 1.0)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        
        glBindVertexArrayOES(vao)
        glDrawElements(GLenum(GL_TRIANGLES),
                       GLsizei(Indices.count),
                       GLenum(GL_UNSIGNED_BYTE),
                       nil)

        context?.presentRenderbuffer(Int(GL_RENDERBUFFER))

        glBindVertexArrayOES(0)
    }
    
}
