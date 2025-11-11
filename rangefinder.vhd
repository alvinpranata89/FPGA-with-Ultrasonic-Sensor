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
           LED : out STD_LOGIC_VECTOR(15 downto 0));
end rangefinder;

architecture Behavioral of rangefinder is

constant CLK_FREQ       : integer := 100_000_000;
constant TRIG_PULSE_US  : integer := 10;
constant MEAS_PERIOD_MS : integer := 60;
constant TRIG_PULSE_TICKS  : integer := (CLK_FREQ / 1_000_000) * TRIG_PULSE_US;
constant MEAS_PERIOD_TICKS : integer := (CLK_FREQ / 1000) * MEAS_PERIOD_MS;

 type state_t is (IDLE, TRIG, WAIT_ECHO_HIGH, MEASURE_ECHO);
   signal state       : state_t := IDLE;

   signal trig_reg    : std_logic := '0';
   signal echo_sync_0 : std_logic := '0';
   signal echo_sync_1 : std_logic := '0';

   signal trig_cnt    : unsigned(15 downto 0) := (others => '0');
   signal period_cnt  : unsigned(31 downto 0) := (others => '0');

   signal echo_cnt    : unsigned(23 downto 0) := (others => '0'); -- enough for max range
   signal echo_latch  : unsigned(23 downto 0) := (others => '0');

   signal distance_cm : unsigned(15 downto 0) := (others => '0');

begin
    trig_out <= trig_reg;
    LED     <= std_logic_vector(distance_cm(15 downto 0));

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

                            -- distance_cm ? echo_cnt / 5800
                            -- (simple integer division)
                            distance_cm <= resize(
                                echo_cnt / to_unsigned(5800, echo_cnt'length),
                                distance_cm'length
                            );

                            state <= IDLE;
                        end if;

                end case;
            end if;
        end if;
    end process;

end Behavioral;
