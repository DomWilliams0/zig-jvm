


pub const Frame = struct {

    operands: *usize,
    local_vars: *usize,

};

// for both operands and localvars, alloc in big chunks 
// new frame(local vars=5,)
// max_stack and max_locals known from code attr