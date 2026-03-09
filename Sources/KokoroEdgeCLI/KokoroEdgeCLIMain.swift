import KokoroEdge

@main
@available(macOS 15, *)
struct KokoroEdgeCLIMain {
    static func main() async {
        await KokoroEdgeCommand.main()
    }
}
