----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 10.11.2025 23:19:47
-- Design Name: 
-- Module Name: rangefinder - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity rangefinder is
    Port ( clk : in STD_LOGIC;
           trig_out : out STD_LOGIC;
           echo_in : in STD_LOGIC;
           BTNC : in STD_LOGIC;
           UART_TXD_IN : in STD_LOGIC;
           UART_RXD_OUT : out STD_LOGIC;
           LED : out STD_LOGIC_VECTOR(15 downto 0));
end rangefinder;

architecture Behavioral of rangefinder is

constant CLK_FREQ       : integer := 100_000_000;
constant BAUD_RATE      : integer := 115_200;
constant UART_STOP_BIT  : integer := 1;
constant bit_timer_limit: integer := CLK_FREQ/BAUD_RATE;
--constant bit_timer      : integer := 0;

constant TRIG_PULSE_US  : integer := 10;
constant MEAS_PERIOD_MS : integer := 60;
constant TRIG_PULSE_TICKS  : integer := (CLK_FREQ / 1_000_000) * TRIG_PULSE_US;
constant MEAS_PERIOD_TICKS : integer := (CLK_FREQ / 1000) * MEAS_PERIOD_MS;

 type state_t is (IDLE, TRIG, WAIT_ECHO_HIGH, MEASURE_ECHO);
 type state_u is (UART_IDLE, UART_B0, UART_B1, UART_CR, UART_LF);
   signal state       : state_t := IDLE;
   signal uart_state  : state_u := UART_IDLE;
   
--   signal uart_bit_cnt: unsigned(7 downto 0) := (others => '0');
   signal uart_bit_cnt: integer := 0;
--   signal bit_timer   : integer := 0;
   signal meas_done : std_logic := '0';
   
   signal trig_reg    : std_logic := '0';
   signal echo_sync_0 : std_logic := '0';
   signal echo_sync_1 : std_logic := '0';

   signal trig_cnt    : unsigned(15 downto 0) := (others => '0');
   signal period_cnt  : unsigned(31 downto 0) := (others => '0');

   signal echo_cnt    : unsigned(23 downto 0) := (others => '0'); -- enough for max range
   signal echo_latch  : unsigned(23 downto 0) := (others => '0');

   signal distance_cm : unsigned(15 downto 0) := (others => '0');
   signal dist_ascii : std_logic_vector(23 downto 0);
   
   signal tx_shift    : std_logic_vector(9 downto 0) := (others => '1');
   signal tx_busy     : std_logic := '0';
   signal bit_timer   : integer range 0 to bit_timer_limit-1 := 0;
   signal bit_index   : integer range 0 to 9 := 0;
   signal tx_data     : std_logic_vector(7 downto 0) := (others => '0');
   signal tx_start    : std_logic := '0';

  function to_ascii(num : integer) return std_logic_vector is
       variable hundreds, tens, ones : integer;
       variable result : std_logic_vector(23 downto 0);
   begin
       hundreds := (num / 100) mod 10;
       tens     := (num / 10) mod 10;
       ones     := num mod 10;
   
       result(23 downto 16) := std_logic_vector(to_unsigned(48 + hundreds, 8));
       result(15 downto 8)  := std_logic_vector(to_unsigned(48 + tens, 8));
       result(7 downto 0)   := std_logic_vector(to_unsigned(48 + ones, 8));
       return result;
  end function;
  
begin
    trig_out <= trig_reg;
    LED     <= std_logic_vector(distance_cm(15 downto 0));
    dist_ascii <= to_ascii(to_integer(distance_cm));  
    
    -- Sync echo to clk domain (2FF)
    process(clk)
    begin
        if rising_edge(clk) then
            echo_sync_0 <= echo_in;
            echo_sync_1 <= echo_sync_0;
        end if;
    end process;

    process(clk)
    begin
        if rising_edge(clk) then
            if BTNC = '1' then
                state       <= IDLE;
                trig_reg    <= '0';
                trig_cnt    <= (others => '0');
                period_cnt  <= (others => '0');
                echo_cnt    <= (others => '0');
                echo_latch  <= (others => '0');
                distance_cm <= (others => '0');
            else
                meas_done <= '0';
                case state is
                    when IDLE =>
                        trig_reg <= '0';
                        if period_cnt < to_unsigned(MEAS_PERIOD_TICKS, period_cnt'length) then
                            period_cnt <= period_cnt + 1;
                        else
                            period_cnt <= (others => '0');
                            trig_cnt   <= (others => '0');
                            state      <= TRIG;
                        end if;

                    when TRIG =>
                        trig_reg <= '1';
                        if trig_cnt < to_unsigned(TRIG_PULSE_TICKS - 1, trig_cnt'length) then
                            trig_cnt <= trig_cnt + 1;
                        else
                            trig_reg <= '0';
                            trig_cnt <= (others => '0');
                            state    <= WAIT_ECHO_HIGH;
                        end if;

                    when WAIT_ECHO_HIGH =>
                        echo_cnt <= (others => '0');
                        if echo_sync_1 = '1' then
                            -- rising edge detected
                            state <= MEASURE_ECHO;
                        elsif period_cnt = to_unsigned(MEAS_PERIOD_TICKS, period_cnt'length) then
                            -- timeout, restart
                            state      <= IDLE;
                            period_cnt <= (others => '0');
                        else
                            period_cnt <= period_cnt + 1;
                        end if;

                    when MEASURE_ECHO =>
                        if echo_sync_1 = '1' then
                            echo_cnt <= echo_cnt + 1;
                        else
                            -- falling edge: latch value and compute distance
                            echo_latch <= echo_cnt;

                            -- distance_cm ? echo_cnt / 
                            distance_cm <= resize(
                                echo_cnt / to_unsigned(5800, echo_cnt'length),
                                distance_cm'length
                            );
                            --uart_state <= UART_DATA;
                            meas_done <= '1'; 
                            state <= IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;  
    
    uart_tx_proc : process(clk)
    begin
        if rising_edge(clk) then
            if BTNC = '1' then
                tx_busy    <= '0';
                UART_RXD_OUT <= '1';
                bit_timer  <= 0;
                bit_index  <= 0;
            else
                if tx_busy = '0' then
                    UART_RXD_OUT <= '1';  -- idle high
                    if tx_start = '1' then
                        -- frame: stop(1) & data(7 downto 0) & start(0)
                        tx_shift <= '1' & tx_data & '0';
                        tx_busy  <= '1';
                        bit_timer <= 0;
                        bit_index <= 0;
                    end if;
                else
                    -- actively transmitting: output current bit
                    UART_RXD_OUT <= tx_shift(bit_index);
    
                    if bit_timer = bit_timer_limit - 1 then
                        bit_timer <= 0;
                        if bit_index = 9 then
                            -- done sending start+8data+stop
                            tx_busy <= '0';
                            UART_RXD_OUT <= '1'; -- back to idle
                        else
                            bit_index <= bit_index + 1;
                        end if;
                    else
                        bit_timer <= bit_timer + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;
    
    print_proc : process(clk)
    begin
        if rising_edge(clk) then
            if BTNC = '1' then
                uart_state  <= UART_IDLE;
                tx_start  <= '0';
            else
                -- default
                tx_start <= '0';
    
                case uart_state is
                    when UART_IDLE =>
                        if meas_done = '1' then
                            -- send first ASCII digit (hundreds)
                            if tx_busy = '0' then
                                tx_data  <= dist_ascii(23 downto 16);
                                tx_start <= '1';
                                uart_state <= UART_B0;
                            end if;
                        end if;
    
                    when UART_B0 =>
                        if tx_busy = '0' then
                            tx_data  <= dist_ascii(15 downto 8);
                            tx_start <= '1';
                            uart_state <= UART_B1;
                        end if;
    
                    when UART_B1 =>
                        if tx_busy = '0' then
                            tx_data  <= dist_ascii(7 downto 0);
                            tx_start <= '1';
                            uart_state <= UART_CR;
                        end if;
    
                    when UART_CR =>
                        if tx_busy = '0' then
                            tx_data  <= x"0D";       -- '\r'
                            tx_start <= '1';
                            uart_state <= UART_LF;
                        end if;
    
                    when UART_LF =>
                        if tx_busy = '0' then
                            tx_data  <= x"0A";       -- '\n'
                            tx_start <= '1';
                            uart_state <= UART_IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;

end Behavioral;
