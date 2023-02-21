from starkware.cairo.common.bitwise import bitwise_and, bitwise_xor
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, HashBuiltin

// Implement a function that sums even numbers from the provided array
func sum_even{bitwise_ptr: BitwiseBuiltin*}(arr_len: felt, arr: felt*, run: felt, idx: felt) -> (sum: felt) {

    if (arr_len == 0) {
        return (0,);
    }

    let (sum_of_rest) = sum_even(arr_len = arr_len - 1, arr = arr + 1, run = 0, idx = 0);
    let (is_odd) = bitwise_and(arr[0], 1);
    let curr_element = arr[0] * (1 - is_odd);
    return (curr_element + sum_of_rest,);
}


