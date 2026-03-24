// DAO Search and Filter Module
// Provides efficient search and filtering capabilities for DAOs
module movedao_addrx::filter {
    use std::string::{Self, String};
    use std::vector;
    use movedao_addrx::dao_core_file::{Self, ImageData};
    use movedao_addrx::featured;

    // Search result structure
    struct DAOSearchResult has copy, drop, store {
        address: address,
        name: String,
        description: String,
        category: String,
        logo: ImageData,
        created_at: u64,
        relevance_score: u64  // Higher score = better match
    }

    // === View Functions ===

    #[view]
    /// Search all DAOs by query string (searches name and description)
    public fun search_daos(
        query: String,
        limit: u64
    ): vector<DAOSearchResult> {
        let all_daos = dao_core_file::get_all_daos();
        let results = vector::empty<DAOSearchResult>();
        let query_lower = to_lowercase(query);
        
        let i = 0;
        let len = vector::length(&all_daos);
        
        while (i < len && vector::length(&results) < limit) {
            let dao_summary = vector::borrow(&all_daos, i);
            let dao_addr = dao_core_file::get_summary_address(dao_summary);
            let name = dao_core_file::get_summary_name(dao_summary);
            let description = dao_core_file::get_summary_description(dao_summary);
            let created_at = dao_core_file::get_summary_created_at(dao_summary);
            
            // Get category and logo from dao_core_file
            let category = dao_core_file::get_dao_category(dao_addr);
            let logo = dao_core_file::get_dao_logo(dao_addr);
            
            // Calculate relevance score
            let score = calculate_relevance_score(
                &query_lower,
                &name,
                &description,
                &category
            );
            
            // Only include if there's a match
            if (score > 0) {
                vector::push_back(&mut results, DAOSearchResult {
                    address: dao_addr,
                    name,
                    description,
                    category,
                    logo,
                    created_at,
                    relevance_score: score
                });
            };
            
            i = i + 1;
        };
        
        // Sort by relevance score (descending)
        sort_by_relevance(&mut results);
        
        results
    }

    #[view]
    /// Filter DAOs by category
    public fun filter_by_category(
        category: String,
        limit: u64
    ): vector<DAOSearchResult> {
        let all_daos = dao_core_file::get_all_daos();
        let results = vector::empty<DAOSearchResult>();
        let category_lower = to_lowercase(category);
        
        let i = 0;
        let len = vector::length(&all_daos);
        
        while (i < len && vector::length(&results) < limit) {
            let dao_summary = vector::borrow(&all_daos, i);
            let dao_addr = dao_core_file::get_summary_address(dao_summary);
            
            let dao_category = dao_core_file::get_dao_category(dao_addr);
            let dao_category_lower = to_lowercase(dao_category);
            let logo = dao_core_file::get_dao_logo(dao_addr);
            
            // Check if category matches
            if (string::length(&category_lower) == 0 || dao_category_lower == category_lower) {
                vector::push_back(&mut results, DAOSearchResult {
                    address: dao_addr,
                    name: dao_core_file::get_summary_name(dao_summary),
                    description: dao_core_file::get_summary_description(dao_summary),
                    category: dao_category,
                    logo,
                    created_at: dao_core_file::get_summary_created_at(dao_summary),
                    relevance_score: 100  // Default score for category matches
                });
            };
            
            i = i + 1;
        };
        
        results
    }

    #[view]
    /// Get newest DAOs
    public fun get_newest_daos(limit: u64): vector<DAOSearchResult> {
        let all_daos = dao_core_file::get_all_daos();
        let results = vector::empty<DAOSearchResult>();
        
        let i = 0;
        let len = vector::length(&all_daos);
        
        while (i < len && vector::length(&results) < limit) {
            let dao_summary = vector::borrow(&all_daos, i);
            let dao_addr = dao_core_file::get_summary_address(dao_summary);
            let category = dao_core_file::get_dao_category(dao_addr);
            let logo = dao_core_file::get_dao_logo(dao_addr);
            
            vector::push_back(&mut results, DAOSearchResult {
                address: dao_addr,
                name: dao_core_file::get_summary_name(dao_summary),
                description: dao_core_file::get_summary_description(dao_summary),
                category,
                logo,
                created_at: dao_core_file::get_summary_created_at(dao_summary),
                relevance_score: 0
            });
            
            i = i + 1;
        };
        
        // Sort by creation date (newest first)
        sort_by_newest(&mut results);
        
        results
    }

    #[view]
    /// Advanced filter with multiple criteria
    public fun advanced_filter(
        query: String,
        category: String,
        min_timestamp: u64,
        max_timestamp: u64,
        sort_by: u8,  // 0=relevance, 1=newest, 2=oldest, 3=name
        limit: u64
    ): vector<DAOSearchResult> {
        let all_daos = dao_core_file::get_all_daos();
        let results = vector::empty<DAOSearchResult>();
        let query_lower = to_lowercase(query);
        let category_lower = to_lowercase(category);
        let has_query = string::length(&query_lower) > 0;
        let has_category = string::length(&category_lower) > 0;
        
        let i = 0;
        let len = vector::length(&all_daos);
        
        while (i < len && vector::length(&results) < limit) {
            let dao_summary = vector::borrow(&all_daos, i);
            let dao_addr = dao_core_file::get_summary_address(dao_summary);
            let name = dao_core_file::get_summary_name(dao_summary);
            let description = dao_core_file::get_summary_description(dao_summary);
            let created_at = dao_core_file::get_summary_created_at(dao_summary);
            
            // Apply timestamp filters
            let passes_time_filter = true;
            if (min_timestamp > 0 && created_at < min_timestamp) {
                passes_time_filter = false;
            };
            if (max_timestamp > 0 && created_at > max_timestamp) {
                passes_time_filter = false;
            };
            
            if (!passes_time_filter) {
                i = i + 1;
                continue
            };
            
            // Get category
            let dao_category = dao_core_file::get_dao_category(dao_addr);
            
            // Apply category filter
            let passes_category = true;
            if (has_category) {
                let dao_category_lower = to_lowercase(dao_category);
                passes_category = (dao_category_lower == category_lower);
            };
            
            if (!passes_category) {
                i = i + 1;
                continue
            };
            
            // Calculate relevance score if query exists
            let score = if (has_query) {
                calculate_relevance_score(
                    &query_lower,
                    &name,
                    &description,
                    &dao_category
                )
            } else {
                100  // Default score when no query
            };
            
            // Only include if passes all filters
            if (score > 0 || !has_query) {
                let logo = dao_core_file::get_dao_logo(dao_addr);
                vector::push_back(&mut results, DAOSearchResult {
                    address: dao_addr,
                    name,
                    description,
                    category: dao_category,
                    logo,
                    created_at,
                    relevance_score: score
                });
            };
            
            i = i + 1;
        };
        
        // Sort based on criteria
        if (sort_by == 0) {
            sort_by_relevance(&mut results);
        } else if (sort_by == 1) {
            sort_by_newest(&mut results);
        } else if (sort_by == 2) {
            sort_by_oldest(&mut results);
        } else if (sort_by == 3) {
            sort_by_name(&mut results);
        };
        
        results
    }

    #[view]
    /// Get all unique categories
    public fun get_all_categories(): vector<String> {
        let all_daos = dao_core_file::get_all_daos();
        let categories = vector::empty<String>();
        
        let i = 0;
        let len = vector::length(&all_daos);
        
        while (i < len) {
            let dao_summary = vector::borrow(&all_daos, i);
            let category = dao_core_file::get_dao_category(dao_core_file::get_summary_address(dao_summary));
            
            // Only add if not empty and not already in list
            if (string::length(&category) > 0 && !vector_contains(&categories, &category)) {
                vector::push_back(&mut categories, category);
            };
            
            i = i + 1;
        };
        
        categories
    }

    #[view]
    /// Get featured DAOs with full search result data
    public fun get_featured_dao_results(): vector<DAOSearchResult> {
        let featured_addresses = featured::get_featured_daos();
        let results = vector::empty<DAOSearchResult>();
        
        let i = 0;
        let len = vector::length(&featured_addresses);
        
        while (i < len) {
            let dao_addr = *vector::borrow(&featured_addresses, i);
            
            // Get DAO information directly by address (Scalability optimization)
            let (name, description, _, _, _, _, _, _, created_at) = dao_core_file::get_dao_info(dao_addr);
            let category = dao_core_file::get_dao_category(dao_addr);
            let logo = dao_core_file::get_dao_logo(dao_addr);
            
            vector::push_back(&mut results, DAOSearchResult {
                address: dao_addr,
                name,
                description,
                category,
                logo,
                created_at,
                relevance_score: 1000  // High score for featured DAOs
            });
            
            i = i + 1;
        };
        
        results
    }

    // === Helper Functions ===

    /// Calculate relevance score based on query match
    fun calculate_relevance_score(
        query: &String,
        name: &String,
        description: &String,
        category: &String
    ): u64 {
        let score = 0u64;
        let query_len = string::length(query);
        
        if (query_len == 0) {
            return 100
        };
        
        let name_lower = to_lowercase(*name);
        let description_lower = to_lowercase(*description);
        let category_lower = to_lowercase(*category);
        
        // Exact matches get highest scores
        if (name_lower == *query) {
            score = score + 1000;
        } else if (contains(&name_lower, query)) {
            score = score + 500;
        };
        
        if (category_lower == *query) {
            score = score + 300;
        } else if (contains(&category_lower, query)) {
            score = score + 150;
        };
        
        if (contains(&description_lower, query)) {
            score = score + 100;
        };
        
        score
    }

    /// Convert string to lowercase (simplified - works for ASCII)
    fun to_lowercase(s: String): String {
        let bytes = string::bytes(&s);
        let result = vector::empty<u8>();
        let i = 0;
        let len = vector::length(bytes);
        
        while (i < len) {
            let byte = *vector::borrow(bytes, i);
            // Convert A-Z (65-90) to a-z (97-122)
            if (byte >= 65 && byte <= 90) {
                vector::push_back(&mut result, byte + 32);
            } else {
                vector::push_back(&mut result, byte);
            };
            i = i + 1;
        };
        
        string::utf8(result)
    }

    /// Check if haystack contains needle
    fun contains(haystack: &String, needle: &String): bool {
        let haystack_bytes = string::bytes(haystack);
        let needle_bytes = string::bytes(needle);
        let haystack_len = vector::length(haystack_bytes);
        let needle_len = vector::length(needle_bytes);
        
        if (needle_len == 0 || needle_len > haystack_len) {
            return false
        };
        
        let i = 0;
        while (i <= haystack_len - needle_len) {
            let match = true;
            let j = 0;
            
            while (j < needle_len) {
                if (*vector::borrow(haystack_bytes, i + j) != *vector::borrow(needle_bytes, j)) {
                    match = false;
                    break
                };
                j = j + 1;
            };
            
            if (match) {
                return true
            };
            
            i = i + 1;
        };
        
        false
    }

    /// Check if vector contains string
    fun vector_contains(vec: &vector<String>, item: &String): bool {
        let i = 0;
        let len = vector::length(vec);
        
        while (i < len) {
            if (vector::borrow(vec, i) == item) {
                return true
            };
            i = i + 1;
        };
        
        false
    }

    /// Sort results by relevance score (descending)
    fun sort_by_relevance(results: &mut vector<DAOSearchResult>) {
        let len = vector::length(results);
        if (len <= 1) return;
        
        // Bubble sort (simple for on-chain)
        let i = 0;
        while (i < len - 1) {
            let j = 0;
            while (j < len - i - 1) {
                let current_score = vector::borrow(results, j).relevance_score;
                let next_score = vector::borrow(results, j + 1).relevance_score;
                
                if (current_score < next_score) {
                    vector::swap(results, j, j + 1);
                };
                
                j = j + 1;
            };
            i = i + 1;
        };
    }

    /// Sort results by creation date (newest first)
    fun sort_by_newest(results: &mut vector<DAOSearchResult>) {
        let len = vector::length(results);
        if (len <= 1) return;
        
        let i = 0;
        while (i < len - 1) {
            let j = 0;
            while (j < len - i - 1) {
                let current_created = vector::borrow(results, j).created_at;
                let next_created = vector::borrow(results, j + 1).created_at;
                
                if (current_created < next_created) {
                    vector::swap(results, j, j + 1);
                };
                
                j = j + 1;
            };
            i = i + 1;
        };
    }

    /// Sort results by creation date (oldest first)
    fun sort_by_oldest(results: &mut vector<DAOSearchResult>) {
        let len = vector::length(results);
        if (len <= 1) return;
        
        let i = 0;
        while (i < len - 1) {
            let j = 0;
            while (j < len - i - 1) {
                let current_created = vector::borrow(results, j).created_at;
                let next_created = vector::borrow(results, j + 1).created_at;
                
                if (current_created > next_created) {
                    vector::swap(results, j, j + 1);
                };
                
                j = j + 1;
            };
            i = i + 1;
        };
    }

    /// Sort results by name (alphabetically)
    fun sort_by_name(results: &mut vector<DAOSearchResult>) {
        let len = vector::length(results);
        if (len <= 1) return;
        
        let i = 0;
        while (i < len - 1) {
            let j = 0;
            while (j < len - i - 1) {
                let current_name = vector::borrow(results, j).name;
                let next_name = vector::borrow(results, j + 1).name;
                
                let current_name_lower = to_lowercase(current_name);
                let next_name_lower = to_lowercase(next_name);
                
                if (is_string_greater(&current_name_lower, &next_name_lower)) {
                    vector::swap(results, j, j + 1);
                };
                
                j = j + 1;
            };
            i = i + 1;
        };
    }

    /// Compare two strings (returns true if a > b)
    fun is_string_greater(a: &String, b: &String): bool {
        let a_bytes = string::bytes(a);
        let b_bytes = string::bytes(b);
        let a_len = vector::length(a_bytes);
        let b_len = vector::length(b_bytes);
        let min_len = if (a_len < b_len) { a_len } else { b_len };
        
        let i = 0;
        while (i < min_len) {
            let a_byte = *vector::borrow(a_bytes, i);
            let b_byte = *vector::borrow(b_bytes, i);
            
            if (a_byte > b_byte) {
                return true
            } else if (a_byte < b_byte) {
                return false
            };
            
            i = i + 1;
        };
        
        // If all bytes are equal up to min_len, longer string is "greater"
        a_len > b_len
    }
}
