import SwiftUI
import AppKit

struct ClipboardListView: View {
    @StateObject private var clipboardManager = ClipboardManager.shared
    @State private var showingExpandedView = false
    
    var body: some View {
        VStack(spacing: 0) {
            Text("Copy Pasta")
                .font(.subheadline)
                .fontWeight(.bold)
                .padding(.vertical, 6)
            
            Divider()
            
            if !showingExpandedView {
                // Preview mode showing last 5 items
                LazyVStack(spacing: 0) {
                    ForEach(Array(clipboardManager.clipboardItems.prefix(5))) { item in
                        ClipboardItemView(item: item)
                            .id(item.id)
                    }
                }
                
                if clipboardManager.clipboardItems.count > 5 {
                    ExpandButton(expanded: $showingExpandedView)
                }
            } else {
                // Expanded view showing all items
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(clipboardManager.clipboardItems) { item in
                                ClipboardItemView(item: item)
                                    .id(item.id)
                            }
                        }
                    }
                    .onChange(of: clipboardManager.clipboardItems) { oldValue, newValue in
                        if let firstId = newValue.first?.id {
                            withAnimation {
                                proxy.scrollTo(firstId, anchor: .top)
                            }
                        }
                    }
                }
                
                ExpandButton(expanded: $showingExpandedView)
            }
        }
        .frame(width: 300)
    }
}

// Extracted button component for better reuse and maintenance
struct ExpandButton: View {
    @Binding var expanded: Bool
    
    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                expanded.toggle()
            }
        }) {
            Text(expanded ? "Show Less" : "Show More")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(Color.gray.opacity(0.1))
    }
}

struct ClipboardItemView: View {
    let item: ClipboardItem
    @State private var isHovered = false
    
    var body: some View {
        Button(action: {
            ClipboardManager.shared.copyToClipboard(item)
        }) {
            HStack {
                contentView
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Image(systemName: "doc.on.doc")
                    .foregroundColor(.secondary)
                    .opacity(isHovered ? 1 : 0)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHovered ? Color.blue.opacity(0.1) : Color.clear)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
    
    @ViewBuilder
    private var contentView: some View {
        switch item.type {
        case .text:
            Text(item.text ?? "")
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .image:
            if let image = item.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 40)
            }
        }
    }
}

// Preview with sample data
struct ClipboardListView_Previews: PreviewProvider {
    static var previews: some View {
        ClipboardListView()
    }
} 
