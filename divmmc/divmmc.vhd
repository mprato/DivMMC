----------------------------------------------------------------------------------
-- Company: 
-- Engineer:   Mario Prato
-- 
-- Create Date:    10:07:18 11/22/2012 
-- Design Name:    divmmc ver. 1.0
-- Module Name:    divmmc - Behavioral 
-- Project Name:  divmmc
-- Target Devices: xc9572xl-vq64
-- Tool versions: ise 12.3
-- Description: zx spectrum mmc sd interface
--
-- Dependencies: 
--
-- Revision: 
-- Revision 0.01 - File Created
-- Additional Comments: 
--
--versione 1.0 
--fitter conf:
--optimize speed
--slew rate slow
--pin termination float
--use global clock
--gnd on unused i/o pin
--macrocell power settings std
--logic optimization speed
--multi level logic optimization
--
--collapsing input limit 54
--collapsing pterm limit 60



library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

---- Uncomment the following library declaration if instantiating
---- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity divmmc is
    Port ( 

--                  z80 cpu signals

	      A        : in  std_logic_vector (15 downto 0);
        D        : inout  std_logic_vector (7 downto 0);
        iorq     : in  std_logic;
        mreq     : in  std_logic;
			  wr       : in  std_logic;
			  rd       : in  std_logic;
        m1       : in  std_logic;
			  reset    : in  std_logic;
			  clock    : in  std_logic; -- Z80 Clock from ula chip (must be negated from edge connector signal)
 
--                  ram/rom signals

        romcs    : out  STD_LOGIC;        -- 1 -> page out spectrum rom
			  romoe    : out STD_LOGIC;         -- eeprom oe pin
			  romwr    : out STD_LOGIC;         -- eeprom wr pin
			  ramoe    : out STD_LOGIC;         -- ram oe pin
			  ramwr    : out  STD_LOGIC;        -- ram wr pin
			  bankout  : out  STD_LOGIC_VECTOR (5 downto 0);	--ram bank	  
			  
--               spi interface 
			  
			  card         : out std_logic_vector(1 downto 0) :="11";	-- Cards CS
			  spi_clock    : out std_logic :='1';     -- card clock
			  spi_dataout  : out std_logic :='1';   -- card data in
			  spi_datain   :	in std_logic :='1';		-- card data out

--                 various 			  
			  poweron      : in  STD_LOGIC; -- low pulse on poweron
			  eprom        : in  STD_LOGIC; -- eprom jumper
        mapcondout   : out  std_logic -- hi when divmmc mem paged in

				
			  );
end divmmc;


architecture Behavioral of divmmc is

 signal address  : std_logic_vector(7 downto 0) ;
 signal zxmmcio : std_logic;
 signal divideio : std_logic;

 signal bank     : std_logic_vector (5 downto 0) := "000000";

 signal mapterm  : std_logic := '0';
 signal mapcond  : std_logic := '0';
 signal conmem   : std_logic  := '0';
 signal mapram   : std_logic  := '0';
 signal automap  : std_logic  := '0';
 
 
 signal map3DXX  : std_logic;
 signal map1F00  : std_logic;

 signal bank3    : std_logic;
 


 
 	-- Transmission states
	type transStates is (
		IDLE, -- Wait for a WR or RD request on port 0xEB
		SAMPLE, -- As there is an I/O request, prepare the transmission; sample the CPU databus if required
		TRANSMIT); -- Transmission (SEND or RECEIVE)
	signal transState : transStates := IDLE; -- Transmission state (initially IDLE)
	
	signal TState : unsigned(3 downto 0) := (others => '0'); -- Counts the T-States during transmission
	
	signal fromSDByte : std_logic_vector(7 downto 0) := (others => '1'); -- Byte received from SD
	signal toSDByte : std_logic_vector(7 downto 0) := (others => '1'); -- Byte to send to SD
	signal toCPUByte : std_logic_vector(7 downto 0) := (others => '1'); -- Byte seen by the CPU after a byte read
 
 
 -- dichiarazioni constanti 
 
 constant divide_control_port : std_logic_vector(7 downto 0) := x"E3"; -- port %11100011
 constant zxmmc_control_port 	: std_logic_vector(7 downto 0) := x"E7"; -- era la porta 31 nella zxmmc+
 constant zxmmc_spi_port 	    : std_logic_vector(7 downto 0) := x"EB"; -- era la porta 63 nella zxmmc+
 
 
 attribute PWR_MODE: string;
 attribute FAST: string;
 attribute BUFG: string;
 
 
 attribute PWR_MODE of spi_clock: signal is "STD";
 attribute PWR_MODE of spi_dataout: signal is "STD";
 attribute PWR_MODE of spi_datain: signal is "STD";
 attribute FAST of spi_clock: signal is "TRUE";
 attribute FAST of spi_dataout: signal is "TRUE";
 attribute FAST of spi_datain: signal is "TRUE";
 
 
begin
 
 address <= A(7 downto 0);
 
 bank3 <= '1' when bank ="000011" else '0';

 -- ROM RAM read write signals


 romoe <= rd or A(15) or A(14) or A(13) or (not conmem and mapram) or (not conmem and not automap) or (not conmem and  eprom);

 romwr <= '0' when wr ='0' and a(13)='0' and a(14)='0' and a(15)='0' and eprom='1' and conmem='1' else '1';
 
 ramoe <= rd or A(15) or A(14) or ( not A(13) and not mapram) or ( not A(13) and conmem) or (not conmem and not automap) or (not conmem and  eprom and not mapram);
 
 ramwr <= wr or A(15) or A(14) or not a(13) or (not conmem and mapram and bank3 ) or (not conmem and not automap) or (not conmem and  eprom and not mapram);

 romcs <= '1' when ((automap and not eprom) or (automap and mapram) or conmem )='1' else '0' ;
 
 --  
 -- Divide Automapping logic			  
 
 mapterm <= '1' when  A(15 downto 0) = x"0000"   or 
                      A(15 downto 0) = x"0008"   or 
                      A(15 downto 0) = x"0038"   or 
                      A(15 downto 0) = x"0066"   or 
                      A(15 downto 0) = x"04c6"   or 
                      A(15 downto 0) = x"0562"   else '0';

 map3DXX   <= '1' when A(15 downto 8) = "00111101"   else '0';             -- mappa 3D00 - 3DFF
 
 map1F00 <= '0' when A(15 downto 3) =   "0001111111111"  else '1';		   		-- 1ff8 - 1fff


 process(mreq)
  begin
  
   if falling_edge(mreq) then
		   if m1='0' then
				 mapcond <= mapterm or map3DXX or (mapcond and map1F00);
				 automap <= mapcond or map3DXX;
		  end if;
	end if;	  
 end process; 

 mapcondout <= mapcond;
 
-- divide control port
												
divideio <='0' when iorq='0' and wr='0' and M1='1' and address = divide_control_port else '1';  	
	
process(divideio,poweron)
 begin
		if poweron ='0' then
		
			bank   <= "000000";
			mapram <= '0';
			conmem <= '0';
			
		elsif	rising_edge(divideio) then
		
			bank(5 downto 0) <= D(5 downto 0);
			mapram           <= D(6) or mapram;
		   conmem          <= D(7);
		end if;
	
end process;	
			
-- ram banks 

 bankout(0) <= bank(0) or not A(13);
 bankout(1) <= bank(1) or not A(13);
 bankout(2) <= bank(2) and    A(13);
 bankout(3) <= bank(3) and    A(13);
 bankout(4) <= bank(4) and    A(13);
 bankout(5) <= bank(5) and    A(13);

-- SD CS signal management
zxmmcio <= '0' when  address = zxmmc_control_port and iorq='0' and m1='1' and wr ='0' else '1';


	process(reset, zxmmcio)
	begin
		if reset = '0' then
				card(0) <= '1';
				card(1) <= '1';
		
		elsif rising_edge(zxmmcio) then
		
				card(0)  <= D(0);
				card(1)  <= D(1);
		
		end if;
	end process;



-- spi transmission/reception

	-- Update transmission state
	process(clock, reset)
	begin
		if reset = '0' then
			transState <= IDLE;
			TState <= (others => '0');
			fromSDByte <= (others => '1');
			toSDByte <= (others => '1');
			toCPUByte <= (others => '1');

		elsif falling_edge(clock) then
			case transState is
			
			when IDLE => -- Intercept a new transmission request (port 0x3F)
				if address = zxmmc_spi_port and iorq='0' and m1='1' then -- If there is a transmission request, prepare to SAMPLE the databus
					transState <= SAMPLE;
				end if;
			
			when SAMPLE =>
					if wr = '0' then -- If it is a SEND request, sample the CPU data bus
						toSDByte <= D;
					end if;
					transState <= TRANSMIT; -- then start the transmission
			
			when TRANSMIT =>
					TState <= TState + 1;

             if TState < 15 then
				 
					if TState(0) = '1' then
						toSDByte   <= toSDByte(6 downto 0)&'1';
						fromSDByte <= fromSDByte(6 downto 0)& spi_datain;
					end if;
             else 
				if TState = 15 then -- transmission is completed; intercept if there is a new transmission request
						if address = zxmmc_spi_port and iorq='0' and m1='1'and wr='0' then							
								toSDByte <= D;
							   transState <= TRANSMIT;
						else -- else we'll go in IDLE state.
							transState <= IDLE;
						--	TState <= "0000";
						end if;
						toCPUByte <= fromSDByte(6 downto 0)& spi_datain;
					end if;
             end if;
			when OTHERS =>
				null;
			end case;
		end if;
		  -- SPI SD Card pins
	SPI_clock <= TState(0);
	spi_dataout <= toSDByte(7);
	end process;
	
  

 D <= toCPUByte when (address = zxmmc_spi_port) and (iorq = '0') and (rd = '0') and m1='1' else "ZZZZZZZZ";


end Behavioral;

