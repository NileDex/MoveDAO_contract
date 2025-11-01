script {
    use movedao_addrx::activity_tracker;

    fun main(account: &signer) {
        // Initialize the global activity tracker
        activity_tracker::initialize(account);
    }
}
