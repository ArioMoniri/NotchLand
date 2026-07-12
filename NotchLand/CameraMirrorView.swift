//
//  CameraMirrorView.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  A self-contained camera "mirror" (self-view) for the expanded notch. Wraps
//  an AVCaptureSession behind a small ObservableObject controller and renders
//  its output through an AVCaptureVideoPreviewLayer, mirrored horizontally so it
//  reads like a hand mirror. Handles authorization gracefully and never crashes
//  when no camera is present.
//

import AVFoundation
import AppKit
import Combine
import SwiftUI

// MARK: - Controller

@MainActor
final class CameraMirrorController: ObservableObject {
    /// Whether the user has granted camera access.
    @Published private(set) var isAuthorized: Bool = false
    /// Whether the capture session is currently running.
    @Published private(set) var isRunning: Bool = false

    /// The capture session the preview layer attaches to.
    let session = AVCaptureSession()

    /// Serial queue so session mutation / start / stop never blocks main.
    private let sessionQueue = DispatchQueue(label: "com.notchland.camera-mirror.session")
    /// True once we have added an input, so we don't reconfigure repeatedly.
    private var isConfigured = false

    init() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        isAuthorized = (status == .authorized)
    }

    // MARK: Public API

    /// Request access if needed, then configure and start the session.
    func start() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            isAuthorized = true
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.isAuthorized = granted
                        if granted {
                            self.configureAndRun()
                        }
                    }
                }
            }
        case .denied, .restricted:
            isAuthorized = false
        @unknown default:
            isAuthorized = false
        }
    }

    /// Stop the session on a background queue and mark it not running.
    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.isRunning = false
                }
            }
        }
    }

    // MARK: Private

    /// Configure inputs once, then start running on the background queue.
    private func configureAndRun() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            if !self.isConfigured {
                self.configureSession()
            }

            // Only start if we actually managed to attach an input.
            guard self.isConfigured else { return }

            if !self.session.isRunning {
                self.session.startRunning()   // Blocks — must stay off main.
            }
            let running = self.session.isRunning
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.isRunning = running
                }
            }
        }
    }

    /// Attach the default video device as an input. Runs on `sessionQueue`.
    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video) else {
            // No camera hardware — leave the session unconfigured.
            return
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            // Device could not be opened (in use, revoked, etc.).
            return
        }

        session.beginConfiguration()
        if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }
        if session.canAddInput(input) {
            session.addInput(input)
            isConfigured = true
        }
        session.commitConfiguration()
    }
}

// MARK: - Preview layer bridge

/// An NSView backed by an AVCaptureVideoPreviewLayer.
final class CameraPreviewNSView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        configureLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        configureLayer()
    }

    private func configureLayer() {
        previewLayer.videoGravity = .resizeAspectFill
        // Mirror horizontally so it behaves like a real mirror (self-view).
        previewLayer.connection?.automaticallyAdjustsVideoMirroring = false
        if previewLayer.connection?.isVideoMirroringSupported == true {
            previewLayer.connection?.isVideoMirrored = true
        }
        layer = previewLayer
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
        // The connection only exists once the session is attached, so keep the
        // mirroring in sync on every layout pass.
        if previewLayer.connection?.isVideoMirroringSupported == true {
            previewLayer.connection?.automaticallyAdjustsVideoMirroring = false
            previewLayer.connection?.isVideoMirrored = true
        }
    }
}

/// SwiftUI wrapper that binds the controller's session to the preview layer.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> CameraPreviewNSView {
        let view = CameraPreviewNSView()
        view.previewLayer.session = session
        return view
    }

    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {
        if nsView.previewLayer.session !== session {
            nsView.previewLayer.session = session
        }
        nsView.previewLayer.frame = nsView.bounds
    }
}

// MARK: - View

struct CameraMirrorView: View {
    @ObservedObject var controller: CameraMirrorController
    var cornerRadius: CGFloat = 14

    init(controller: CameraMirrorController, cornerRadius: CGFloat = 14) {
        self.controller = controller
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        ZStack {
            if controller.isAuthorized && controller.isRunning {
                CameraPreview(session: controller.session)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                placeholder
            }
        }
        .onAppear { controller.start() }
        .onDisappear { controller.stop() }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.black.opacity(0.35))
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(.secondary)
                    Text(controller.isAuthorized ? "Starting camera…" : "Camera access needed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(8)
            }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
