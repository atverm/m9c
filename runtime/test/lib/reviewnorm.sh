# reviewnorm.sh -- the review page WITHOUT ITS LINE NUMBERS, which is
# what runtime/test/review/*.txt records and reviewdiff compares.
# Sourced by reviewgen.sh and reviewdiff.sh.
#
# `m9c --review' prints every site with its line, because a reviewer
# goes and looks.  A RECORDED page cannot carry them: a comment added
# at the top of a module moves every line below it, and the gate
# would go red on a page whose every claim is unchanged -- which it
# did, on its second day, for a one-line comment in Review.m9 itself.
# A gate that is red for line shifts is a gate nobody reads when a
# KEPT parameter appears.  So the recorded page keeps what a site IS
# -- `NewIn', `Put.hidden', the counts -- and drops where it stands:
#
#     pool parameters      1   168 NewIn        ->   ... 1   NewIn
#     arguments         1140   passed over, a type unknown: 389 -- line 231, 317, ...
#                                               ->   ... 1140   passed over, a type unknown: 389
#
# Only the indented rows are touched; the heading line has numbers of
# its own (`14 procedures with a body, 11 of them functions').
review_norm () {
  sed -E -e '/^  /s/ -- line [0-9, .]+$//' \
         -e '/^  /s/(   |, )[0-9]+ ([^ ,])/\1\2/g'
}
