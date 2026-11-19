import SwiftUI

struct FirstLaunchView: View {
    var onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "cursorarrow.motionlines")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .foregroundColor(.blue)
            
            Text("Welcome to GlideCursor")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                    Text("GlideCursor is currently OFF")
                }
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text("To enable, click the menu bar icon and turn GlideCursor on.")
                }
                HStack {
                    Image(systemName: "hand.raised.fill").foregroundColor(.orange)
                    Text("Accessibility permissions are required to control the cursor.")
                }
                HStack {
                    Image(systemName: "hand.point.up.left.fill").foregroundColor(.blue)
                    Text("Flick and lift to glide. Touch the trackpad to stop.")
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(10)
            
            Button("Open System Settings") {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                NSWorkspace.shared.open(url)
            }
            
            Spacer()
            
            Button("Get Started") {
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(40)
        .frame(width: 600)
    }
}
