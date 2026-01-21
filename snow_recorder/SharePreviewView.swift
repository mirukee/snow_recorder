import SwiftUI

/// 라이딩 결과 공유용 프리뷰 화면 (모달)
/// 배경 이미지 위에 데이터를 오버레이
struct SharePreviewView: View {
    @Environment(\.dismiss) var dismiss
    
    // 더미 데이터 (실제로는 주입받아야 함)
    var speed: Double = 45.0
    var distance: Double = 5.2
    var time: String = "01:20:30"
    
    var body: some View {
        ZStack {
            // 1. 배경 이미지 (이미지는 에셋에 있어야 하지만, 없으면 색상으로 대체)
            Color.gray.ignoresSafeArea()
            
            // 실제 이미지 사용 예시:
            // Image("sample_riding_photo")
            //     .resizable()
            //     .aspectRatio(contentMode: .fill)
            //     .ignoresSafeArea()
            
            // 어두운 오버레이 (텍스트 가독성 확보)
            Color.black.opacity(0.3).ignoresSafeArea()
            
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white)
                    }
                    .padding()
                }
                
                Spacer()
                
                // 2. 데이터 오버레이 디자인
                VStack(alignment: .leading, spacing: 10) {
                    Text("SNOW RECORD")
                        .font(.headline)
                        .foregroundColor(.green)
                    
                    HStack(alignment: .bottom) {
                        Text("\(Int(speed))")
                            .font(.system(size: 80, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                        Text("km/h")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.bottom, 12)
                    }
                    
                    HStack(spacing: 20) {
                        VStack(alignment: .leading) {
                            Text("DISTANCE")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                            Text("\(String(format: "%.1f", distance))km")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                        
                        VStack(alignment: .leading) {
                            Text("TIME")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                            Text(time)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(30)
                // 유리창 효과 (Glassmorphism)
                .background(.ultraThinMaterial) 
                .cornerRadius(20)
                .padding()
                .padding(.bottom, 40)
            }
        }
    }
}

#Preview {
    SharePreviewView()
}
