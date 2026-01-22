import SwiftUI
import PhotosUI

struct SharePreviewView: View {
    @Environment(\.dismiss) var dismiss
    let session: RunSession
    
    // MARK: - State
    @State private var selectedItem: PhotosPickerItem?
    @State private var backgroundUIImage: UIImage?
    @State private var showShareSheet = false
    @State private var imageToShare: UIImage?
    @State private var showSaveToast = false
    
    // Image Transform
    @GestureState private var pinchScale: CGFloat = 1.0
    @State private var steadyScale: CGFloat = 1.0
    @GestureState private var panOffset: CGSize = .zero
    @State private var steadyOffset: CGSize = .zero
    
    var currentScale: CGFloat { steadyScale * pinchScale }
    var currentOffset: CGSize {
        CGSize(
            width: steadyOffset.width + panOffset.width,
            height: steadyOffset.height + panOffset.height
        )
    }
    
    let primaryColor = Color(red: 107/255, green: 249/255, blue: 6/255)
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background
                Color.black.ignoresSafeArea()
                
                // Image with gestures
                if let uiImage = backgroundUIImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(currentScale)
                        .offset(currentOffset)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .ignoresSafeArea()
                        .gesture(
                            MagnificationGesture()
                                .updating($pinchScale) { value, state, _ in
                                    state = value
                                }
                                .onEnded { value in
                                    steadyScale = min(max(steadyScale * value, 1.0), 3.0)
                                }
                        )
                        .simultaneousGesture(
                            DragGesture()
                                .updating($panOffset) { value, state, _ in
                                    state = value.translation
                                }
                                .onEnded { value in
                                    steadyOffset = CGSize(
                                        width: steadyOffset.width + value.translation.width,
                                        height: steadyOffset.height + value.translation.height
                                    )
                                }
                        )
                } else {
                    LinearGradient(
                        colors: [Color(white: 0.15), Color.black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                }
                
                // Gradient overlay
                LinearGradient(
                    colors: [.black.opacity(0.3), .clear, .black.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
                
                // Stats
                VStack {
                    Spacer()
                    previewStatsView
                        .padding(.horizontal, 20)
                        .padding(.bottom, 140)
                }
                .allowsHitTesting(false)
                
                // Brand Watermark (Top Left)
                VStack {
                    HStack {
                        brandView
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 120)
                    Spacer()
                }
                .allowsHitTesting(false)
                
                // Save Toast
                if showSaveToast {
                    VStack {
                        Spacer()
                        Text("✓ 저장 완료")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color.black.opacity(0.8))
                            .cornerRadius(25)
                            .padding(.bottom, 180)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                // Controls
                VStack {
                    HStack {
                        Button(action: { dismiss() }) {
                            ZStack {
                                Circle().fill(Color.white).frame(width: 44, height: 44)
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.black)
                            }
                            .shadow(radius: 4)
                        }
                        
                        Spacer()
                        
                        Text("PREVIEW")
                            .font(.system(size: 14, weight: .bold))
                            .tracking(2)
                            .foregroundColor(.white)
                            .shadow(radius: 4)
                        
                        Spacer()
                        
                        PhotosPicker(selection: $selectedItem, matching: .images) {
                            ZStack {
                                Circle().fill(Color.white).frame(width: 44, height: 44)
                                Image(systemName: "photo")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.black)
                            }
                            .shadow(radius: 4)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 60)
                    
                    if backgroundUIImage != nil {
                        Text("핀치/드래그로 사진 조절")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.top, 8)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 16) {
                        Button(action: shareToStory) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.up.circle.fill")
                                Text("SHARE TO STORY")
                            }
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.vertical, 16)
                            .padding(.horizontal, 24)
                            .background(primaryColor)
                            .clipShape(Capsule())
                        }
                        
                        Button(action: saveToPhotos) {
                            ZStack {
                                Circle()
                                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
                                    .background(Circle().fill(Color.black.opacity(0.3)))
                                    .frame(width: 56, height: 56)
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .padding(.bottom, 50)
                }
            }
        }
        .onChange(of: selectedItem) { newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    backgroundUIImage = uiImage
                    steadyScale = 1.0
                    steadyOffset = .zero
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = imageToShare {
                ShareSheet(activityItems: [image])
            }
        }
    }
    
    // MARK: - Brand Watermark
    var brandView: some View {
        HStack(spacing: 8) {
            Image(systemName: "snowflake")
                .font(.system(size: 22))
                .foregroundColor(primaryColor)
            Text("SNOW RECORD")
                .font(.system(size: 18, weight: .black))
                .italic()
                .foregroundColor(.white)
        }
        .padding(10)
        .background(Color.black.opacity(0.5))
        .cornerRadius(4)
    }
    
    // MARK: - Preview Stats (small, for screen)
    var previewStatsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Runs
            Text("\(session.runCount) RUNS")
                .font(.system(size: 12, weight: .black))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white)
                .foregroundColor(.black)
                .rotationEffect(.degrees(2))
                .padding(.bottom, 8)
            
            // Distance
            VStack(alignment: .leading, spacing: 0) {
                Text("TOTAL DISTANCE")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.7))
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", session.distance / 1000.0))
                        .font(.system(size: 72, weight: .black))
                        .foregroundColor(primaryColor)
                        .shadow(color: primaryColor.opacity(0.5), radius: 8)
                    Text("KM")
                        .font(.system(size: 28, weight: .black))
                        .italic()
                        .foregroundColor(.white)
                }
            }
            .padding(.bottom, 12)
            
            // Speed
            VStack(alignment: .leading, spacing: 2) {
                Text("TOP VELOCITY")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                Text("MAX SPEED \(String(format: "%.1f", session.maxSpeed)) KM/H")
                    .font(.system(size: 16, weight: .black))
                    .foregroundColor(.white)
            }
            .padding(10)
            .background(Color.black.opacity(0.5))
            .cornerRadius(4)
            .padding(.bottom, 20)
            
            // Divider
            Rectangle().fill(Color.white.opacity(0.3)).frame(height: 1).padding(.bottom, 16)
            
            // Footer
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("KOREA").font(.system(size: 28, weight: .bold)).foregroundColor(.white)
                    Text(session.locationName).font(.system(size: 16)).foregroundColor(.white.opacity(0.7))
                    HStack(spacing: 4) {
                        Image(systemName: "calendar").font(.system(size: 12)).foregroundColor(primaryColor)
                        Text(session.startTime.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(primaryColor)
                    }
                    .padding(.top, 4)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(alignment: .bottom, spacing: 2) {
                        Rectangle().fill(Color.white).frame(width: 3, height: 32)
                        Rectangle().fill(Color.white).frame(width: 2, height: 20)
                        Rectangle().fill(Color.white).frame(width: 5, height: 28)
                        Rectangle().fill(Color.white).frame(width: 2, height: 14)
                        Rectangle().fill(Color.white).frame(width: 6, height: 32)
                        Rectangle().fill(Color.white).frame(width: 2, height: 18)
                        Rectangle().fill(primaryColor).frame(width: 3, height: 32)
                    }
                    Text("REC-025").font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.6))
                }
            }
        }
    }
    
    // MARK: - Export Stats (large, for 1080x1920)
    func exportStatsView() -> some View {
        let s: CGFloat = 3.0 // Scale factor for export
        
        return VStack(alignment: .leading, spacing: 0) {
            // Runs
            Text("\(session.runCount) RUNS")
                .font(.system(size: 12 * s, weight: .black))
                .padding(.horizontal, 10 * s)
                .padding(.vertical, 4 * s)
                .background(Color.white)
                .foregroundColor(.black)
                .rotationEffect(.degrees(2))
                .padding(.bottom, 8 * s)
            
            // Distance
            VStack(alignment: .leading, spacing: 0) {
                Text("TOTAL DISTANCE")
                    .font(.system(size: 10 * s, weight: .bold))
                    .tracking(2 * s)
                    .foregroundColor(.white.opacity(0.7))
                HStack(alignment: .lastTextBaseline, spacing: 4 * s) {
                    Text(String(format: "%.1f", session.distance / 1000.0))
                        .font(.system(size: 72 * s, weight: .black))
                        .foregroundColor(primaryColor)
                        .shadow(color: primaryColor.opacity(0.5), radius: 8 * s)
                    Text("KM")
                        .font(.system(size: 28 * s, weight: .black))
                        .italic()
                        .foregroundColor(.white)
                }
            }
            .padding(.bottom, 12 * s)
            
            // Speed
            VStack(alignment: .leading, spacing: 2 * s) {
                Text("TOP VELOCITY")
                    .font(.system(size: 9 * s, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                Text("MAX SPEED \(String(format: "%.1f", session.maxSpeed)) KM/H")
                    .font(.system(size: 16 * s, weight: .black))
                    .foregroundColor(.white)
            }
            .padding(10 * s)
            .background(Color.black.opacity(0.5))
            .cornerRadius(4 * s)
            .padding(.bottom, 20 * s)
            
            // Divider
            Rectangle().fill(Color.white.opacity(0.3)).frame(height: 1 * s).padding(.bottom, 16 * s)
            
            // Footer
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4 * s) {
                    Text("KOREA").font(.system(size: 28 * s, weight: .bold)).foregroundColor(.white)
                    Text(session.locationName).font(.system(size: 16 * s)).foregroundColor(.white.opacity(0.7))
                    HStack(spacing: 4 * s) {
                        Image(systemName: "calendar").font(.system(size: 12 * s)).foregroundColor(primaryColor)
                        Text(session.startTime.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 11 * s, weight: .bold))
                            .foregroundColor(primaryColor)
                    }
                    .padding(.top, 4 * s)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4 * s) {
                    HStack(alignment: .bottom, spacing: 2 * s) {
                        Rectangle().fill(Color.white).frame(width: 3 * s, height: 32 * s)
                        Rectangle().fill(Color.white).frame(width: 2 * s, height: 20 * s)
                        Rectangle().fill(Color.white).frame(width: 5 * s, height: 28 * s)
                        Rectangle().fill(Color.white).frame(width: 2 * s, height: 14 * s)
                        Rectangle().fill(Color.white).frame(width: 6 * s, height: 32 * s)
                        Rectangle().fill(Color.white).frame(width: 2 * s, height: 18 * s)
                        Rectangle().fill(primaryColor).frame(width: 3 * s, height: 32 * s)
                    }
                    Text("REC-025").font(.system(size: 9 * s, design: .monospaced)).foregroundColor(.white.opacity(0.6))
                }
            }
        }
    }
    
    // MARK: - Export View (1080x1920)
    func exportView() -> some View {
        let width: CGFloat = 1080
        let height: CGFloat = 1920
        
        return ZStack {
            Color.black
            
            if let uiImage = backgroundUIImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(currentScale)
                    .offset(x: currentOffset.width * 3, y: currentOffset.height * 3)
                    .frame(width: width, height: height)
                    .clipped()
            } else {
                LinearGradient(colors: [Color(white: 0.15), .black], startPoint: .top, endPoint: .bottom)
            }
            
            LinearGradient(colors: [.black.opacity(0.3), .clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
            
            VStack {
                Spacer()
                exportStatsView()
                    .padding(.horizontal, 60)
                    .padding(.bottom, 120)
            }
            
            // Brand at top left
            VStack {
                HStack {
                    exportBrandView()
                    Spacer()
                }
                .padding(.horizontal, 60)
                .padding(.top, 100)
                Spacer()
            }
        }
        .frame(width: width, height: height)
    }
    
    func exportBrandView() -> some View {
        let s: CGFloat = 3.0
        return HStack(spacing: 8 * s) {
            Image(systemName: "snowflake")
                .font(.system(size: 22 * s))
                .foregroundColor(primaryColor)
            Text("SNOW RECORD")
                .font(.system(size: 18 * s, weight: .black))
                .italic()
                .foregroundColor(.white)
        }
        .padding(10 * s)
        .background(Color.black.opacity(0.5))
        .cornerRadius(4 * s)
    }
    
    // MARK: - Actions
    @MainActor
    func shareToStory() {
        let renderer = ImageRenderer(content: exportView())
        renderer.scale = 1.0
        guard let image = renderer.uiImage else { return }
        
        if let url = URL(string: "instagram-stories://share"),
           UIApplication.shared.canOpenURL(url) {
            UIPasteboard.general.setItems([["com.instagram.sharedSticker.backgroundImage": image.pngData()!]], options: [.expirationDate: Date().addingTimeInterval(300)])
            UIApplication.shared.open(url)
        } else {
            imageToShare = image
            showShareSheet = true
        }
    }
    
    @MainActor
    func saveToPhotos() {
        let renderer = ImageRenderer(content: exportView())
        renderer.scale = 1.0
        if let image = renderer.uiImage {
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            withAnimation(.spring()) {
                showSaveToast = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    showSaveToast = false
                }
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
