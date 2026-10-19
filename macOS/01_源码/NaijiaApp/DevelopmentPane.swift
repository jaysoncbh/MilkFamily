#if DEBUG
import SwiftUI
import NaijiaCore

struct DevelopmentPane: View {
    @ObservedObject var store: AppStore
    @State private var tokenText = "1000000"
    @State private var hatchID = "random"
    var onReview: () -> Void

    private var tokens: Int? { DevelopmentSimulation.parseTokens(tokenText) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !store.developmentTesting {
                Text(L("独立测试存档，可恢复正式进度。")).font(.system(size: 11)).foregroundStyle(.secondary)
                Button(L("开始测试")) { store.beginDevelopmentTesting() }.buttonStyle(.bordered)
            } else {
                HStack {
                    Badge(text: L("测试存档"), color: .orange)
                    Spacer()
                    Button(L("查看界面"), action: onReview).buttonStyle(.bordered).controlSize(.small)
                }
                Text(L("\(compact(store.state.totalTokens)) Token · \(store.state.coins) 奶币 · 免费 \(store.state.freeDraws) 次"))
                    .font(.system(size: 10)).monospacedDigit()
                Text(L(store.onboardingStage == .choosePartner ? "尚未选择伙伴" : "\(store.active.name) · \(store.state.phase == .cultivating ? "培养中" : "孵蛋中")"))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Divider()
                SectionCaption(text: L("设定 Token"))
                HStack {
                    TextField(L("如 20M"), text: $tokenText).textFieldStyle(.roundedBorder).accessibilityLabel(L("测试Token数量")).help(L("支持整数、K、M、B；累计用量可超过 1000M"))
                    Button(L("设定")) { if let tokens { store.developerSetTokens(tokens) } }.buttonStyle(.bordered).disabled(tokens == nil || !store.game.readyForGrowth)
                }
                Text(L("重算进度")).font(.system(size: 9)).foregroundStyle(.secondary)
                    .help(L("以所选初始伙伴重演成长、奶币和免费次数，清除其他测试收集结果"))
                if !store.game.readyForGrowth { Text(L("先选择伙伴并领取待机卡")).font(.system(size: 10)).foregroundStyle(.secondary) }
                if tokens == nil { Text(L("请输入非负整数")).font(.system(size: 10)).foregroundStyle(.orange) }
                SectionCaption(text: L("追加用量"))
                HStack(spacing: 7) {
                    ForEach([100_000, 1_000_000, 5_000_000], id: \.self) { amount in
                        Button(L("+\(compact(amount))")) { store.developerAddTokens(amount, hatchCharacterID: selectedHatch) }.buttonStyle(.bordered)
                    }
                    Button(L("追加")) { if let tokens { store.developerAddTokens(tokens, hatchCharacterID: selectedHatch) } }.buttonStyle(.bordered).disabled(tokens == nil || tokens == 0)
                }.controlSize(.small).disabled(!store.game.readyForGrowth)
                HStack {
                    Button(store.state.phase == .cultivating ? "解锁全部动作" : "完成孵化") { store.developerFinishStage(hatchCharacterID: selectedHatch) }.buttonStyle(.bordered)
                    Button(L("开始孵蛋")) { store.developerPrepareIncubation() }.buttonStyle(.bordered).disabled(store.state.phase != .cultivating)
                }.controlSize(.small).disabled(!store.game.readyForGrowth)
                Picker(L("孵化结果"), selection: $hatchID) {
                    Text(L("随机")).tag("random")
                    ForEach(store.library.characters.filter { $0.rarityCode >= store.state.eggGrade }) { character in
                        Text(L(character.name)).tag(character.id)
                    }
                }.font(.system(size: 10))
                    .onChange(of: store.state.eggGrade) { _, _ in hatchID = "random" }
                Divider()
                HStack {
                    Button(L("重置进度")) { store.developerResetEverything() }.buttonStyle(.bordered)
                    Button(L("撤销")) { store.developerUndo() }.buttonStyle(.bordered).disabled(store.developmentUndoState == nil)
                }.controlSize(.small)
                Text(L("清空测试，重新选伙伴")).font(.system(size: 9)).foregroundStyle(.secondary)
                Button(L("备份")) { store.showDevelopmentBackups() }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(mint).help(L("查看修改前的自动备份"))
                Divider()
                Button(L("退出测试")) { Task { await store.endDevelopmentTesting() } }
                    .buttonStyle(.bordered)
                Text(L("恢复正式进度")).font(.system(size: 9)).foregroundStyle(.secondary).help(L("测试期间的真实用量不补发成长奖励"))
            }
        }.disabled(store.developerBusy)
    }

    private var selectedHatch: String? { hatchID == "random" ? nil : hatchID }
}
#endif
