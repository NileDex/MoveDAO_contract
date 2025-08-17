script {
    use dao_addr::activity_tracker;

    fun main(account: &signer) {
        // Initialize the global activity tracker
        activity_tracker::initialize(account);
    }
}
