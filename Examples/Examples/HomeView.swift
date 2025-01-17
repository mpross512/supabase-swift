//
//  HomeView.swift
//  Examples
//
//  Created by Guilherme Souza on 23/12/22.
//

import SwiftUI

struct HomeView: View {
  @Environment(AuthController.self) var auth

  @State private var mfaStatus: MFAStatus?

  var body: some View {
    TodoListView()
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Sign out") {
            Task {
              try! await supabase.auth.signOut()
            }
          }
        }
      }
      .task {
//        mfaStatus = await verifyMFAStatus()
      }
      .sheet(unwrapping: $mfaStatus) { $mfaStatus in
        MFAFlow(status: mfaStatus)
      }
  }

  private func verifyMFAStatus() async -> MFAStatus? {
    do {
      let aal = try await supabase.auth.mfa.getAuthenticatorAssuranceLevel()
      switch (aal.currentLevel, aal.nextLevel) {
      case ("aal1", "aal1"):
        return .unenrolled
      case ("aal1", "aal2"):
        return .unverified
      case ("aal2", "aal2"):
        return .verified
      case ("aal2", "aal1"):
        return .disabled
      default:
        return nil
      }
    } catch {
      return nil
    }
  }
}

struct HomeView_Previews: PreviewProvider {
  static var previews: some View {
    HomeView()
  }
}
