(** Word data type *)
module Word =
  struct
    type t = Z.t * int (* the integer is the size in bits *)

    let to_string w =
      let s   = String.escaped "0x%"             in
      let fmt = Printf.sprintf "%s%#dx" s (snd w) in
      Printf.sprintf "0x%s" (Z.format fmt (fst w))

    let size w = snd w
		     
    let compare (w1, sz1) (w2, sz2) = 
      let n = Z.compare w1 w2 in
      if n = 0 then sz1 - sz2 else n

    let equal v1 v2 = compare v1 v2 = 0
					
    let zero sz	= Z.zero, sz
			    
    let one sz = Z.one, sz

    let add w1 w2 =
      let w' = Z.add (fst w1) (fst w2) in
      w', max (String.length (Z.to_bits w')) (max (size w1) (size w2))

    let sub w1 w2 =
      let w' = Z.sub (fst w1) (fst w2) in
      w', String.length (Z.to_bits w')
			
   				  
    let of_int v sz = v, sz
				    
    let to_int v = fst v
			    
    let of_string v n =
      try
	let v' = Z.of_string v in
	if String.length (Z.to_bits v') > n then
	  Log.error (Printf.sprintf "word %s too large to fit into %d bits" v n)
	else
	  v', n
      with _ -> Log.error (Printf.sprintf "Illegal conversion from Z.t to word of %s" v)

    let hash w = Z.hash (fst w)
			
    let size_extension (v, sz) n = 
      if sz >= n then (v, sz)
      else 
	(v, n)

    (** returns the lowest n bit of the given int *)
    let truncate_int i n =
      Z.logand i (Z.sub (Z.shift_left Z.one n) Z.one)
	       
    (** [truncate w n] returns the lowest n bits of w *)
    let truncate (w, sz) n =
      if sz < n then
	w, sz
      else
	truncate_int w n, n

    (** binary operation on words supposed to have the same size *)
    (** result is truncated to have size of the operands *)
    let binary op (w1, sz) (w2, _) =
      truncate_int (op w1 w2) sz, sz

    let unary op (w, sz) =
      truncate_int (op w) sz, sz

    let shift_left (w, sz) i = Z.shift_left w i, sz-i
    let shift_right (w, sz) i = Z.shift_right w i, sz-i
							
  end

(** Address Data Type *)
module Address =
  struct

    module A = struct

      (* these memory regions are supposed not to overlap *)
      type region =
	| Global (** abstract base address of global variables and code *)
	| Stack  (** abstract base address of the stack *)
	| Heap   (** abstract base address of a dynamically allocated memory block *)
	    
	    
      let string_of_region r =
	match r with
	| Global -> "Global"
	| Stack  -> "Stack"
	| Heap   -> "Heap"

      type t = region * Word.t

      let compare (r1, w1) (r2, w2) =
	let n = compare r1 r2 in
	if n <> 0 then
	  n
	else
	  Word.compare w1 w2

      let equal (r1, w1) (r2, w2) =
	let b = r1 = r2 in
	if b then Word.equal w1 w2
	else
	  false
	    
      let of_string r a n =
	if !Config.mode = Config.Protected then 
	  let w = Word.of_string a n in
	  if Word.compare w (Word.zero n) < 0 then
	    Log.error "Tried to create negative address"
	  else
	      r, w
	else
	  Log.error "Address generation for this memory mode not yet managed"

      let to_string (r, w) = Printf.sprintf "(%s, %s)" (string_of_region r) (Word.to_string w)
	
      (** returns the offset of the address *)
      let to_int (_r, w) = Word.to_int w
				   
      let of_int r i o = r, (i, o)

      let of_word w = Global, w
			     
      let size a = Word.size (snd a)
		       
      let add_offset (r, w) o' =
	let n = Word.size w in
	let w' = Word.add w (Word.of_int o' n) in
	if Word.size w' > n then
	  begin
	    Log.from_analysis "Data.Address: overflow when tried to add an offset to an address: ";
	    r, Word.truncate w' n
	  end
	else
	  r, w'
	       
      let to_word (_r, w) sz =
	if Word.size w >= sz then
	  w
	else
	  raise (Invalid_argument "overflow when tried to convert an address to a word")
		
      let sub v1 v2 =
	match v1, v2 with
	| (r1, w1), (r2, w2)  when r1 = r2 ->
	   let w = Word.sub w1 w2 in
	   if Word.compare w (Word.zero (Word.size w1)) < 0 then
	     Log.error "invalid address substraction"
	   else
	    Word.to_int w
	| _, _ 	-> Log.error "invalid address substraction"

      let binary op ((r1, w1): t) ((r2, w2): t): t =
	let r' =
	  match r1, r2 with
	  | Global, r | r, Global -> r
	  | r1, r2                ->
	     if r1 = r2 then r1 else Log.error "Invalid binary operation on addresses of different regions"
	in
	  r', Word.binary op w1 w2

      let unary op (r, w) = r, Word.unary op w

      let size_extension (r, w) sz = r, Word.size_extension w sz

      let shift_left (r, w) i = r, Word.shift_left w i
      let shift_right (r, w) i = r, Word.shift_right w i
    end
    include A
    module Set = Set.Make(A)
			 
  end
