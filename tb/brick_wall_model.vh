// Independent integer-coordinate version of the approved software preview.
// Include inside a testbench module. No RTL hierarchy or bit-slice arithmetic.
function [11:0] brick_wall_model;
    input integer x, y;
    integer course, shifted, bx, by, variant;
    begin
        course = y / 8;
        shifted = x + (course % 2) * 8;
        bx = shifted % 16;
        by = y % 8;
        variant = ((shifted / 16) ^ course ^ (course / 2)) % 4;
        case (variant)
            0: brick_wall_model = 12'h987;
            1: brick_wall_model = 12'ha98;
            2: brick_wall_model = 12'h998;
            3: brick_wall_model = 12'h887;
        endcase
        if (bx == 0 || by == 0) brick_wall_model = 12'h433;
        else if (bx == 15 || by == 7) brick_wall_model = 12'h654;
        else if (by == 1 || bx == 1) brick_wall_model = 12'hba8;
        else if ((by == 3 && (bx == 4 || bx == 5) && variant != 2) ||
                 (by == 5 && bx == 11 && variant == 2)) brick_wall_model = 12'hba8;
        else if (by == 5 && (bx == 7 || bx == 8) && variant == 1) brick_wall_model = 12'h776;
    end
endfunction
