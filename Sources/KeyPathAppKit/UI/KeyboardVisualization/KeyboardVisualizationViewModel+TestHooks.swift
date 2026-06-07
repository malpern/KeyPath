#if DEBUG
    extension KeyboardVisualizationViewModel {
        func simulateHoldActivated(key: String, action: String) {
            handleHoldActivated(key: key, action: action)
        }

        func simulateTapActivated(key: String, action: String) {
            handleTapActivated(key: key, action: action)
        }

        func simulateTcpKeyInput(key: String, action: String) {
            handleTcpKeyInput(key: key, action: action)
        }
    }
#endif
