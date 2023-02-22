%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.starknet.common.syscalls import get_caller_address, get_block_timestamp
from starkware.cairo.common.math import unsigned_div_rem, assert_le_felt, assert_le, assert_nn
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.math_cmp import is_le_felt
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.pow import pow
from starkware.cairo.common.hash_state import hash_init, hash_update
from starkware.cairo.common.bitwise import bitwise_and, bitwise_xor, bitwise_or
from lib.constants import TRUE, FALSE

// Structs
//#########################################################################################

struct Consortium {
    chairperson: felt,
    proposal_count: felt,
}

struct Member {
    votes: felt,
    prop: felt,
    ans: felt,
}

struct Answer {
    text: felt,
    votes: felt,
}

struct Proposal {
    type: felt,  // whether new answers can be added
    win_idx: felt,  // index of preffered option
    ans_idx: felt,
    deadline: felt,
    over: felt,
}

// remove in the final asnwerless
struct Winner {
    highest: felt,
    idx: felt,
}

// Storage
//#########################################################################################

@storage_var
func consortium_idx() -> (idx: felt) {
}

@storage_var
func consortiums(consortium_idx: felt) -> (consortium: Consortium) {
}

@storage_var
func members(consortium_idx: felt, member_addr: felt) -> (memb: Member) {
}

@storage_var
func proposals(consortium_idx: felt, proposal_idx: felt) -> (win_idx: Proposal) {
}

@storage_var
func proposals_idx(consortium_idx: felt) -> (idx: felt) {
}

@storage_var
func proposals_title(consortium_idx: felt, proposal_idx: felt, string_idx: felt) -> (
    substring: felt
) {
}

@storage_var
func proposals_link(consortium_idx: felt, proposal_idx: felt, string_idx: felt) -> (
    substring: felt
) {
}

@storage_var
func proposals_answers(consortium_idx: felt, proposal_idx: felt, answer_idx: felt) -> (
    answers: Answer
) {
}

@storage_var
func voted(consortium_idx: felt, proposal_idx: felt, member_addr: felt) -> (true: felt) {
}

@storage_var
func answered(consortium_idx: felt, proposal_idx: felt, member_addr: felt) -> (true: felt) {
}

// External functions
//#########################################################################################

@external
func create_consortium{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    let (caller) = get_caller_address();
    // create the consortium
    let newConsortium = Consortium(chairperson = caller, proposal_count = 0);
    let (consortiumIdx) = consortium_idx.read();
    consortiums.write(consortiumIdx, newConsortium);
    consortium_idx.write(consortiumIdx + 1);

    // make chairperson member
    let chairMember = Member(votes = 100, prop = 1, ans = 1);
    members.write(consortiumIdx, caller, chairMember);
    
    return ();
}

@external
func add_proposal{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    consortium_idx: felt,
    title_len: felt,
    title: felt*,
    link_len: felt,
    link: felt*,
    ans_len: felt,
    ans: felt*,
    type: felt,
    deadline: felt,
) {
    alloc_locals;
    let (local proposalIdx) = proposals_idx.read(consortium_idx);
    proposals_idx.write(consortium_idx, proposalIdx + 1);
    let newProp = Proposal(type = type, win_idx = 0, ans_idx = ans_len, deadline =  deadline, over = 0);
    proposals.write(consortium_idx, proposalIdx, newProp);
    init_answer(consortium_idx, proposalIdx, ans_len, ans, 0);
    load_selector(title_len, title, 0, proposalIdx, consortium_idx, 0, 0);
    load_selector(link_len, link, 0, proposalIdx, consortium_idx, 1, 0);
    return ();
}

@external
func add_member{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    consortium_idx: felt, member_addr: felt, prop: felt, ans: felt, votes: felt
) {
    let (caller) = get_caller_address();
    let (consortium) = consortiums.read(consortium_idx);
    let chairPerson = consortium.chairperson;
    assert caller = chairPerson;
    let newMember = Member(votes = votes, prop = prop, ans = ans);
    members.write(consortium_idx, member_addr, newMember);

    return ();
}

@external
func add_answer{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    consortium_idx: felt, proposal_idx: felt, string_len: felt, string: felt*
) {

    let (caller) = get_caller_address();
    let (callerInfo) = members.read(consortium_idx, caller);
    let (proposalInfo) = proposals.read(consortium_idx, proposal_idx);
    let (hasAnswered) = answered.read(consortium_idx, proposal_idx, caller);
    assert callerInfo.ans = 1;
    assert proposalInfo.type = 1;
    assert hasAnswered = 0;
    assert string_len = 1;

    let answer_idx = proposalInfo.ans_idx;
    proposals_answers.write(consortium_idx, proposal_idx, answer_idx, Answer(text = [string], votes = 0));
    proposals.write(consortium_idx,
                    proposal_idx,
                    Proposal(
                    type = proposalInfo.type,
                    proposalInfo.win_idx,
                    proposalInfo.ans_idx + 1,
                    proposalInfo.deadline,
                    proposalInfo.over)
                    );


    answered.write(consortium_idx, proposal_idx, caller, 1);
    
    return ();
}

@external
func vote_answer{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    consortium_idx: felt, proposal_idx: felt, answer_idx: felt
) {
    let (caller) = get_caller_address();
    let (hasVoted) = voted.read(consortium_idx, proposal_idx, caller);
    assert hasVoted = 0;
    let (callerInfo) = members.read(consortium_idx, caller);
    let callerVotes = callerInfo.votes;
    assert_nn(callerVotes); 

    let (answer) = proposals_answers.read(consortium_idx, proposal_idx, answer_idx);
    let currVotes = answer.votes;
    let text = answer.text;
    let newVotes = currVotes + callerVotes;
    let newAnswer = Answer(text = text, votes = newVotes);
    proposals_answers.write(consortium_idx, proposal_idx, answer_idx, newAnswer);
    voted.write(consortium_idx, proposal_idx, caller, 1);

    return ();
}

@external
func tally{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    consortium_idx: felt, proposal_idx: felt
) -> (win_idx: felt) {

    let (win_idx) = find_highest(consortium_idx, proposal_idx, 0, 0, 0);
    let (proposal) = proposals.read(consortium_idx, proposal_idx);
    return (win_idx,);
}


// Internal functions
//#########################################################################################


func find_highest{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    consortium_idx: felt, proposal_idx: felt, highest: felt, idx: felt, countdown: felt
) -> (idx: felt) {
    let (proposal) = proposals.read(consortium_idx, proposal_idx);
    let maxIdx = proposal.ans_idx;
    if (maxIdx == countdown) {
        return (idx,);
    }

    let (ans) = proposals_answers.read(consortium_idx, proposal_idx, countdown);
    let votes = ans.votes;
    let isLe = is_le(votes, highest);
    if (isLe == 0) {
        let (idx) = find_highest(consortium_idx, proposal_idx, votes, countdown, countdown + 1);
        return (idx,);
        
    } else {
        let (idx) = find_highest(consortium_idx, proposal_idx, highest, idx, countdown + 1);
        return (idx,);
    }
 
}

// Loads it based on length, internall calls only
func load_selector{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    string_len: felt,
    string: felt*,
    slot_idx: felt,
    proposal_idx: felt,
    consortium_idx: felt,
    selector: felt,
    offset: felt,
) {

    if (offset == string_len) {
        return ();
    }

    let text = string[offset];

    if (selector == 0) {
        proposals_title.write(consortium_idx, proposal_idx, offset, text);
    } else {
        proposals_link.write(consortium_idx, proposal_idx, offset, text);
    }

    load_selector(string_len, string, slot_idx, proposal_idx, consortium_idx, selector, offset + 1);

    return ();
}

func init_answer{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    consortium_idx: felt,
    proposal_idx: felt,
    ans_len: felt,
    ans: felt*,
    runningIdx: felt
) {

    if (runningIdx == ans_len) {
        return ();
    }

    let text = ans[runningIdx];
    let newAns = Answer(text = text, votes = 0);
    proposals_answers.write(consortium_idx, proposal_idx, runningIdx, newAns);
    init_answer(consortium_idx, proposal_idx, ans_len, ans, runningIdx + 1);

    return ();

}