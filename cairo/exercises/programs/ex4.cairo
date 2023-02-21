// Return summation of every number below and up to including n
func calculate_sum(n: felt) -> (sum: felt) {
    if ( n == 1) {
        return (1,);
    }

    let (sum_of_rest,) = calculate_sum(n = n - 1);
    return (n + sum_of_rest,);
}
