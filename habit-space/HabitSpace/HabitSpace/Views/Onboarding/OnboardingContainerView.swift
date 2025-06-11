import SwiftUI

struct OnboardingContainerView<Content: View>: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var viewModel: OnboardingViewModel
    let content: Content
    let showBackButton: Bool
    let showNextButton: Bool
    let nextButtonAction: (() -> Void)?
    
    init(
        viewModel: OnboardingViewModel,
        showBackButton: Bool = true,
        showNextButton: Bool = true,
        nextButtonAction: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.viewModel = viewModel
        self.showBackButton = showBackButton
        self.showNextButton = showNextButton
        self.nextButtonAction = nextButtonAction
        self.content = content()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            ProgressView(value: viewModel.currentStep.progress)
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                .padding(.horizontal)
                .padding(.top, 8)
            
            // Main content
            VStack(spacing: 20) {
                // Title and description
                VStack(spacing: 12) {
                    Text(viewModel.currentStep.title)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    Text(viewModel.currentStep.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.top, 20)
                .padding(.bottom, 10)
                
                // Content
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                Spacer()
                
                // Navigation buttons
                HStack {
                    if showBackButton && viewModel.currentStep != .welcome {
                        Button(action: {
                            withAnimation {
                                viewModel.previous()
                            }
                        }) {
                            HStack {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    Spacer()
                    
                    if showNextButton {
                        Button(action: {
                            nextButtonAction?()
                            viewModel.next()
                        }) {
                            HStack {
                                Text(viewModel.currentStep == .completion ? "Get Started" : "Next")
                                if viewModel.currentStep != .completion {
                                    Image(systemName: "chevron.right")
                                }
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .cornerRadius(10)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.bottom, 30)
                .padding(.horizontal)
            }
        }
        .navigationBarHidden(true)
    }
}

// MARK: - Preview
struct OnboardingContainerView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingContainerView(viewModel: OnboardingViewModel()) {
            Text("Content goes here")
        }
    }
}
