// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import AVFoundation
import XCTest

@testable import camera_avfoundation

final class CameraSetDeviceOrientationTests: XCTestCase {
  private func createCamera() -> (Camera, MockCaptureConnection, MockCaptureConnection) {
    let camera = CameraTestUtils.createTestCamera()

    let mockCapturePhotoOutput = MockCapturePhotoOutput()
    let mockPhotoCaptureConnection = MockCaptureConnection()
    mockPhotoCaptureConnection.isVideoOrientationSupported = true

    mockCapturePhotoOutput.connectionWithMediaTypeStub = { _ in mockPhotoCaptureConnection }
    camera.capturePhotoOutput = mockCapturePhotoOutput

    let mockCaptureVideoDataOutput = MockCaptureVideoDataOutput()
    let mockVideoCaptureConnection = MockCaptureConnection()
    mockVideoCaptureConnection.isVideoOrientationSupported = true

    mockCaptureVideoDataOutput.connectionWithMediaTypeStub = { _ in mockVideoCaptureConnection }
    camera.captureVideoOutput = mockCaptureVideoDataOutput

    return (camera, mockPhotoCaptureConnection, mockVideoCaptureConnection)
  }

  func testSetDeviceOrientation_setsOrientationsOfCaptureConnections() {
    let (camera, mockPhotoCaptureConnection, mockVideoCaptureConnection) = createCamera()
    var photoSetVideoOrientationCalled = false
    mockPhotoCaptureConnection.setVideoOrientationStub = { orientation in
      // Device orientation is flipped compared to video orientation. When UIDeviceOrientation
      // is landscape left the video orientation should be landscape right.
      XCTAssertEqual(orientation, .landscapeRight)
      photoSetVideoOrientationCalled = true
    }

    var videoSetVideoOrientationCalled = false
    mockVideoCaptureConnection.setVideoOrientationStub = { orientation in
      // Panda CCD keeps preview/recording portrait; Flutter presents rotation.
      XCTAssertEqual(orientation, .portrait)
      videoSetVideoOrientationCalled = true
    }

    camera.deviceOrientation = .landscapeLeft

    XCTAssertTrue(photoSetVideoOrientationCalled)
    XCTAssertTrue(videoSetVideoOrientationCalled)
  }

  func
    testSetDeviceOrientation_setsLockedOrientationsOfCaptureConnection_ifCaptureOrientationIsLocked()
  {
    let (camera, mockPhotoCaptureConnection, mockVideoCaptureConnection) = createCamera()
    var photoSetVideoOrientationCalled = false
    mockPhotoCaptureConnection.setVideoOrientationStub = { orientation in
      XCTAssertEqual(orientation, .portraitUpsideDown)
      photoSetVideoOrientationCalled = true
    }

    var videoSetVideoOrientationCalled = false
    mockVideoCaptureConnection.setVideoOrientationStub = { orientation in
      XCTAssertEqual(orientation, .portrait)
      videoSetVideoOrientationCalled = true
    }

    camera.lockCaptureOrientation(PlatformDeviceOrientation.portraitDown)

    camera.deviceOrientation = .landscapeLeft

    XCTAssertTrue(photoSetVideoOrientationCalled)
    XCTAssertTrue(videoSetVideoOrientationCalled)
  }

  func testSetDeviceOrientation_updatesPhotoButNotVideo_whileRecording() {
    let (camera, mockPhotoCaptureConnection, mockVideoCaptureConnection) = createCamera()

    camera.startVideoRecording(completion: { _ in }, messengerForStreaming: nil)

    mockPhotoCaptureConnection.setVideoOrientationStub = { XCTAssertEqual($0, .landscapeRight) }
    mockVideoCaptureConnection.setVideoOrientationStub = { _ in XCTFail() }

    camera.deviceOrientation = .landscapeLeft
  }

  func testSetDeviceOrientation_doesNotSetOrientations_forDuplicateUpdates() {
    let (camera, mockPhotoCaptureConnection, mockVideoCaptureConnection) = createCamera()
    var photoSetVideoOrientationCallCount = 0
    mockPhotoCaptureConnection.setVideoOrientationStub = { _ in
      photoSetVideoOrientationCallCount += 1
    }

    var videoSetVideoOrientationCallCount = 0
    mockVideoCaptureConnection.setVideoOrientationStub = { _ in
      videoSetVideoOrientationCallCount += 1
    }

    camera.deviceOrientation = .landscapeRight
    camera.deviceOrientation = .landscapeRight

    XCTAssertEqual(photoSetVideoOrientationCallCount, 1)
    XCTAssertEqual(videoSetVideoOrientationCallCount, 1)
  }
}
