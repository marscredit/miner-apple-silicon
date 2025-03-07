var body: some View {
    VStack(spacing: 24) {
        Text("Mars Credit Miner")
            .font(.gunship(size: 32))
            .foregroundColor(.white)
        
        VStack(alignment: .leading, spacing: 8) {
            Text("Mining Address:")
                .font(.gunship(size: 14))
                .foregroundColor(.gray)
            Text(miningAddress)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.white)
        }
        
        Text("Balance: \(String(format: "%.2f", balance)) MARS")
            .font(.gunship(size: 18))
            .foregroundColor(.white)
        
        if isMining {
            Button("Stop Mining") {
                stopMining()
            }
            .miningButtonStyle(isDestructive: true)
            
            HStack {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text("Mining Active")
                    .font(.gunship(size: 14))
                    .foregroundColor(.green)
                Text("\(String(format: "%.2f", hashRate)) MH/s")
                    .font(.gunship(size: 14))
                    .foregroundColor(.white)
            }
            .padding(.vertical, 8)
        } else {
            Button("Start Mining") {
                startMining()
            }
            .miningButtonStyle()
        }
    }
    .padding(32)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black)
} 