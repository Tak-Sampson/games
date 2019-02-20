# Tic Tac Toe
require 'pry'
class Board
  attr_reader :squares
  WINNING_LINES = [[1, 2, 3], [4, 5, 6], [7, 8, 9]] +
                  [[1, 4, 7], [2, 5, 8], [3, 6, 9]] +
                  [[1, 5, 9], [3, 5, 7]]
  CORNERS = [1, 3, 7, 9]
  SIDES = [2, 4, 6, 8]

  def initialize
    @squares = {}
    reset
  end

  def []=(key, marker)
    @squares[key].marker = marker
  end

  def unmarked_keys
    @squares.keys.select { |key| @squares[key].unmarked? }
  end

  def full?
    unmarked_keys.empty?
  end

  def someone_won?
    !!winning_marker
  end

  # returns winning marker or nil
  def winning_marker
    WINNING_LINES.each do |line|
      candidate = @squares[line[0]]
      markers = @squares.values_at(*line).map(&:marker)
      if candidate.marked? && markers.uniq.size == 1
        return candidate.marker
      end
    end
    nil
  end

  # rubocop:disable Metrics/AbcSize
  def draw
    puts "     |     |   "
    puts "  #{@squares[1]}  |  #{@squares[2]}  |  #{@squares[3]}"
    puts "     |     |   "
    puts "-----+-----+-----"
    puts "     |     |   "
    puts "  #{@squares[4]}  |  #{@squares[5]}  |  #{@squares[6]}"
    puts "     |     |   "
    puts "-----+-----+-----"
    puts "     |     |   "
    puts "  #{@squares[7]}  |  #{@squares[8]}  |  #{@squares[9]}"
    puts "     |     |   "
  end
  # rubocop:enable Metrics/AbcSize

  def reset
    (1..9).each { |k| @squares[k] = Square.new }
  end

  def adjacent_corners(side)
    CORNERS.select{ |corner| (corner - side).abs == 1 || corner % 3 == side % 3 }
  end

  def adjacent_sides(corner)
    SIDES.select{ |side| (corner - side).abs == 1 || corner % 3 == side % 3 }
  end

  def keys_marked_by(marker)
    squares.select{ |_, square| square.marker == marker }.keys
  end
end

class Square
  INITIAL_MARKER = ' '

  attr_accessor :marker

  def initialize
    @marker = INITIAL_MARKER
  end

  def to_s
    @marker
  end

  def unmarked?
    marker == INITIAL_MARKER
  end

  def marked?
    !unmarked?
  end
end

class Player
  attr_reader :name, :marker
  @@roster = {}

  def initialize(player_type)
    @name = valid_name(player_type)
    @marker = valid_mark(player_type)
    @@roster[name] = marker
  end

  private

  def valid_name(player_type)
    case player_type
    when :human then human_name
    when :computer then computer_name
    end
  end

  def valid_mark(player_type)
    case player_type
    when :human then human_mark
    when :computer then computer_mark
    end
  end

  def human_name
    response = nil
    loop do
      puts "Welcome to Tic Tac Toe!!!"
      puts "What is your name?"
      response = gets.chomp
      break unless response == ''
      puts "Invalid entry. Name must contain at least one character."
    end
    response
  end

  def human_mark
    response = ''
    puts "Ok #{name}, what marker to you want? (must be one character)"
    loop do
      response = gets.chomp
      break if response.length == 1 && response != ' '
      puts "Invalid entry\n #{name}, choose a marker (must be one character)"
    end
    response.upcase
  end

  def computer_name
    name = ['HAL 9000', 'Master Control', 'Bender',
            'Deep Thought', 'R2D2'].sample
    name = 'Computer' if @@roster.key?(name)
    name
  end

  def computer_mark
    @@roster.value?('X') ? 'O' : 'X'
  end
end

class Strategy
  def initialize(*tactics)
    @sequence = tactics
  end

  def apply(marker, board)
    recommended_move = board.unmarked_keys.sample
    @sequence.each do |tactic|
      recommendation = tactic.call(marker, board)
      if recommendation
        recommended_move = recommendation
        break
      end
    end
    recommended_move
  end
end

# Some Tactics -----------------------------------------------------------

claim_center = lambda do |_, board|
  return 5 if board.unmarked_keys.include?(5)
  nil
end

block_three = lambda do |marker, board|
  Board::WINNING_LINES.each do |line|
    markers = line.map{ |key| board.squares[key].marker }
    opponent_marker = markers.find{ |mark| mark != marker &&
      mark != Square::INITIAL_MARKER }
    if markers.count(opponent_marker) == 2 && !markers.include?(marker)
      return line.find{ |key| board.squares[key].marker == Square::INITIAL_MARKER }
    end
  end
  nil
end

complete_three = lambda do |marker, board|
  Board::WINNING_LINES.each do |line|
    markers = line.map{ |key| board.squares[key].marker }
    if markers.count(marker) == 2 && markers.include?(Square::INITIAL_MARKER)
      return line.find{ |key| board.squares[key].marker == Square::INITIAL_MARKER }
    end
  end
  nil
end

claim_corner = lambda do |_, board|
  Board::CORNERS.select{ |corner| board.squares[corner].unmarked? }.sample
end

l_stop = lambda do |marker, board|
  corner_squares = board.squares.select{ |k, _| Board::CORNERS.include?(k) }.values
  taken_corner = corner_squares.find{ |square| square.marker != marker && square.marked? }
  side_squares = board.squares.select{ |k, _| Board::SIDES.include?(k) }.values
  taken_side = side_squares.find{ |square| square.marker != marker && square.marked? }
  side_key = board.squares.key(taken_side)
  if taken_corner && taken_side
    return (board.adjacent_corners(side_key) & board.unmarked_keys).sample
  end
  nil
end

diffuse_corner_trap = lambda do |marker, board|
  markers = board.squares.values.map(&:marker)
  opponent_marker = markers.find{ |mark| mark != marker &&
      mark != Square::INITIAL_MARKER }
  opponent_keys = board.keys_marked_by(opponent_marker)
  if opponent_keys == [1, 9] || opponent_keys == [3, 7] 
    return (Board::SIDES & board.unmarked_keys).sample
  else
    return nil
  end
end

comp_strat = Strategy.new(complete_three, block_three, claim_center, 
  diffuse_corner_trap, l_stop, claim_corner) 

# ------------------------------------------------------------------------

class TTTGame
  ROUNDS_PER_GAME = 5

  attr_reader :board, :human, :computer, :current_player, :points, :round

  def initialize(computer_strategy)
    @board = Board.new
    @human = Player.new(:human)
    @computer = Player.new(:computer)
    @current_player = human
    @points = { human: 0, computer: 0, ties: 0 }
    @round = 1
    @computer_strategy = computer_strategy
  end

  def play_unlimited
    clear
    display_welcome_message
    loop do
      display_board
      loop do
        current_player_moves
        break if board.full? || board.someone_won?
        clear_screen_and_display_board if human_turn?
      end
      display_result
      break unless play_again?
      reset
      display_play_again_message
    end
    display_goodbye_message
  end

  def play_fixed_rounds
    clear
    display_alternate_welcome
    loop do
      display_board_round_score
      loop do
        current_player_moves
        break if board.full? || board.someone_won?
        clear_screen_display_brs if human_turn?
      end
      display_lingering_result
      update_points_and_round
      break if overall_winner
      reset
    end
    display_alternate_goodbye
  end

  private

  def display_board
    puts "#{human.name}: #{human.marker}   #{computer.name}: #{computer.marker}"
    puts ""
    board.draw
    puts ""
  end

  def display_board_round_score
    display_round_and_score
    display_board
  end

  def clear_screen_and_display_board
    clear
    display_board
  end

  def clear_screen_display_brs
    clear
    display_board_round_score
  end

  def display_welcome_message
    puts "Welcome to Tic Tac Toe!"
    puts ''
  end

  def display_alternate_welcome
    puts "Welcome to Tic Tac Toe!"
    puts "First player to win #{ROUNDS_PER_GAME} rounds wins!"
    puts ''
  end

  def display_goodbye_message
    puts "Thanks for playing Tic Tac Toe! Goodbye!"
  end

  def display_alternate_goodbye
    winner = nil
    case overall_winner
    when :human then winner = human.name
    when :computer then winner = computer.name
    end
    puts "Overall winner: #{winner}!"
    puts "Thanks for playing Tic Tac Toe! Goodbye!"
  end

  def human_moves
    puts "Choose a square from the following: "\
      "(#{board.unmarked_keys.join(', ')})"
    square = nil
    loop do
      square = gets.chomp.to_i
      break if board.unmarked_keys.include?(square)
      puts "Sorry, that is not a valid choice"
    end
    board[square] = human.marker
  end

  def computer_moves
    recommendation = @computer_strategy.apply(computer.marker, board)
    if !recommendation || board.squares[recommendation].marked?
      board[board.unmarked_keys.sample] = computer.marker
    else
      board[recommendation] = computer.marker
    end
  end

  def current_player_moves
    case current_player
    when human
      human_moves
      @current_player = computer
    when computer
      computer_moves
      @current_player = human
    end
  end

  def human_turn?
    current_player == human
  end

  def display_result
    clear_screen_and_display_board
    case board.winning_marker
    when human.marker
      puts "You won!"
    when computer.marker
      puts "Computer won!"
    else
      puts "It's a tie!"
    end
    puts ''
  end

  def display_lingering_result
    display_result
    sleep 2
  end

  def play_again?
    answer = nil
    loop do
      puts "Would you like to play again?"
      answer = gets.chomp.downcase
      break if %w(y n).include?(answer)
      puts "Sorry, must be y or n"
    end
    answer == 'y'
  end

  def display_round
    puts "Round #{round}:"
    puts ''
  end

  def display_score
    puts "Score:    #{human.name}: #{points[:human]}"\
      "   #{computer.name}: #{points[:computer]}   "\
      "ties: #{points[:ties]}"
    puts ''
  end

  def display_round_and_score
    display_round
    display_score
  end

  def update_points_and_round
    @round += 1
    marker = board.winning_marker
    if marker == human.marker
      @points[:human] += 1
    elsif marker == computer.marker
      @points[:computer] += 1
    end
  end

  def overall_winner
    if points[:computer] == ROUNDS_PER_GAME
      return :computer
    elsif points[:human] == ROUNDS_PER_GAME
      return :human
    else
      return nil
    end
  end

  def clear
    system 'clear'
  end

  def reset
    clear
    board.reset
    @current_player = human
  end

  def display_play_again_message
    puts "Let's play again!"
    puts ''
  end
end

game = TTTGame.new(comp_strat)
game.play_fixed_rounds
