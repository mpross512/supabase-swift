//
//  AuthClientTests.swift
//
//
//  Created by Guilherme Souza on 23/10/23.
//

import XCTest
@_spi(Internal) import _Helpers
import ConcurrencyExtras

@testable import Auth

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

final class AuthClientTests: XCTestCase {
  var eventEmitter: MockEventEmitter!
  var sessionManager: MockSessionManager!

  var sut: AuthClient!

  override func setUp() {
    super.setUp()

    eventEmitter = MockEventEmitter()
    sessionManager = MockSessionManager()
    sut = makeSUT()
  }

  override func tearDown() {
    super.tearDown()

    let completion = { [weak sut] in
      XCTAssertNil(sut, "sut should not leak")
    }

    defer { completion() }

    sut = nil
    eventEmitter = nil
    sessionManager = nil
  }

  func testOnAuthStateChanges() async {
    let session = Session.validSession
    sessionManager.returnSession = .success(session)

    let events = LockIsolated([AuthChangeEvent]())

    let handle = await sut.onAuthStateChange { event, _ in
      events.withValue {
        $0.append(event)
      }
    }
    addTeardownBlock { [weak handle] in
      XCTAssertNil(handle, "handle should be deallocated")
    }

    XCTAssertEqual(events.value, [.initialSession])
  }

  func testAuthStateChanges() async throws {
    let session = Session.validSession
    sessionManager.returnSession = .success(session)

    let events = ActorIsolated([AuthChangeEvent]())

    let (stream, continuation) = AsyncStream<Void>.makeStream()

    let authStateStream = await sut.authStateChanges

    let streamTask = Task {
      for await (event, _) in authStateStream {
        await events.withValue {
          $0.append(event)
        }

        continuation.yield()
      }
    }

    _ = await stream.first { _ in true }

    let receivedEvents = await events.value
    XCTAssertEqual(receivedEvents, [.initialSession])

    streamTask.cancel()
  }

  func testSignOut() async throws {
    sessionManager.returnSession = .success(.validSession)

    try await withDependencies {
      $0.api.execute = { _ in .stub() }
    } operation: {
      try await sut.signOut()

      do {
        _ = try await sut.session
      } catch AuthError.sessionNotFound {
      } catch {
        XCTFail("Unexpected error.")
      }

      XCTAssertEqual(eventEmitter.emitReceivedParams.map(\.0), [.signedOut])
    }
  }

  func testSignOutWithOthersScopeShouldNotRemoveLocalSession() async throws {
    sessionManager.returnSession = .success(.validSession)

    try await withDependencies {
      $0.api.execute = { _ in .stub() }
    } operation: {
      try await sut.signOut(scope: .others)

      XCTAssertFalse(sessionManager.removeCalled)
    }
  }

  func testSignOutShouldRemoveSessionIfUserIsNotFound() async throws {
    sessionManager.returnSession = .success(.validSession)

    await withDependencies {
      $0.api.execute = { _ in throw AuthError.api(AuthError.APIError(code: 404)) }
    } operation: {
      do {
        try await sut.signOut()
      } catch AuthError.api {
      } catch {
        XCTFail("Unexpected error: \(error)")
      }

      let emitedParams = eventEmitter.emitReceivedParams
      let emitedEvents = emitedParams.map(\.0)
      let emitedSessions = emitedParams.map(\.1)

      XCTAssertEqual(emitedEvents, [.signedOut])
      XCTAssertEqual(emitedSessions.count, 1)
      XCTAssertNil(emitedSessions[0])

      XCTAssertEqual(sessionManager.removeCallCount, 1)
    }
  }

  func testSignOutShouldRemoveSessionIfJWTIsInvalid() async throws {
    sessionManager.returnSession = .success(.validSession)

    await withDependencies {
      $0.api.execute = { _ in throw AuthError.api(AuthError.APIError(code: 401)) }
    } operation: {
      do {
        try await sut.signOut()
      } catch AuthError.api {
      } catch {
        XCTFail("Unexpected error: \(error)")
      }

      let emitedParams = eventEmitter.emitReceivedParams
      let emitedEvents = emitedParams.map(\.0)
      let emitedSessions = emitedParams.map(\.1)

      XCTAssertEqual(emitedEvents, [.signedOut])
      XCTAssertEqual(emitedSessions.count, 1)
      XCTAssertNil(emitedSessions[0])

      XCTAssertEqual(sessionManager.removeCallCount, 1)
    }
  }

  private func makeSUT() -> AuthClient {
    let configuration = AuthClient.Configuration(
      url: clientURL,
      headers: ["Apikey": "dummy.api.key"],
      localStorage: Dependencies.localStorage,
      logger: nil
    )

    let sut = AuthClient(
      configuration: configuration,
      sessionManager: sessionManager,
      codeVerifierStorage: .mock,
      api: .mock,
      eventEmitter: eventEmitter,
      sessionStorage: .mock,
      logger: nil
    )

    return sut
  }
}

extension Response {
  static func stub(_ body: String = "", code: Int = 200) -> Response {
    Response(
      data: body.data(using: .utf8)!,
      response: HTTPURLResponse(
        url: clientURL,
        statusCode: code,
        httpVersion: nil,
        headerFields: nil
      )!
    )
  }
}
