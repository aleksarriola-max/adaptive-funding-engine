module adaptive_funding::program {
    use sui::event;
    use std::string::{Self, String};

    // === Objects ===

    public struct Program has key {
        id: UID,
        name: String,
        description: String,
        active: bool,
    }

    public struct ManagerCap has key, store {
        id: UID,
        program_id: address,
    }

    public struct ReviewerCap has key, store {
        id: UID,
        program_id: address,
        reviewer: address,
    }

    // === Events ===

    public struct ProgramCreated has copy, drop {
        program_id: address,
        name: String,
    }

    public struct ReviewerAdded has copy, drop {
        program_id: address,
        reviewer: address,
    }

    // === Functions ===

    public fun create_program(
        name: vector<u8>,
        description: vector<u8>,
        ctx: &mut TxContext,
    ) {
        let program = Program {
            id: object::new(ctx),
            name: string::utf8(name),
            description: string::utf8(description),
            active: true,
        };
        let program_id = object::id_address(&program);
        let name_copy = program.name;
        event::emit(ProgramCreated { program_id, name: name_copy });
        transfer::share_object(program);
        transfer::transfer(ManagerCap {
            id: object::new(ctx),
            program_id,
        }, ctx.sender());
    }

    public fun issue_reviewer_cap(
        cap: &ManagerCap,
        reviewer: address,
        ctx: &mut TxContext,
    ) {
        event::emit(ReviewerAdded { program_id: cap.program_id, reviewer });
        transfer::transfer(ReviewerCap {
            id: object::new(ctx),
            program_id: cap.program_id,
            reviewer,
        }, reviewer);
    }

    // === Getters ===

    public fun program_id(cap: &ManagerCap): address { cap.program_id }
    public fun reviewer_address(cap: &ReviewerCap): address { cap.reviewer }
    public fun reviewer_program_id(cap: &ReviewerCap): address { cap.program_id }
    public fun is_active(program: &Program): bool { program.active }
    public fun name(program: &Program): &String { &program.name }
}
