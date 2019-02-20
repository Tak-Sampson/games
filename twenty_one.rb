# Twenty One

class Participant
  attr_reader :name, :hands

  def initialize
    @hands = [Hand.new]
  end

  def live_hands?
    hands.any?(&:live?)
  end

  def hit(hand, deck)
    deck.deal(hand)
    hand
  end

  def stay(hand)
    hand.stay
  end

  def reset_hands
    @hands = [Hand.new]
  end
end

class Player < Participant
  attr_reader :splits, :score
  @@roster = []

  def initialize
    super
    @name = set_name
    @@roster << self
    @splits = 0
    @score = { hands_won: 0, hands_played: 0 }
  end

  def split(hand)
    hand_1 = Hand.new(hand.cards[0])
    hand_2 = Hand.new(hand.cards[1])
    @hands.delete(hand)
    hand_1.record_got_via_split
    hand_2.record_got_via_split
    @hands << hand_1
    @hands << hand_2
    @splits += 1
    hand_1
  end

  def reset_splits
    @splits = 0
  end

  private

  def set_name
    response = nil
    loop do
      clear_and_player_welcome
      response = gets.chomp
      if response.empty?
        puts "Names must have at least one character. Please try again."
      elsif response.downcase == 'dealer'
        puts "Name 'Dealer' is reserved. Please select another."
      elsif @@roster.map(&:name).map(&:downcase).include?(response.downcase)
        puts "Name already taken. Please select another."
      else
        break
      end
    end
    response
  end

  def clear_and_player_welcome
    sleep_and_clear
    puts 'Welcome to Twenty One!'
    puts ''
    puts "Player #{@@roster.size + 1}, what is your name?"
  end

  def sleep_and_clear
    sleep 1.5
    system 'clear'
  end
end

class Dealer < Participant
  OPTIONS = [:hit, :stay]
  def initialize
    super
    @name = 'Dealer'
  end
end

class Deck
  attr_reader :cards
  SUITS = ['diamonds', 'clubs', 'hearts', 'spades']
  FACES = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A']

  def initialize(deck_num= 1)
    @cards = replenish_cards(deck_num)
  end

  def deal(hand)
    hand << cards.pop
  end

  def size
    cards.size
  end

  def empty?
    cards.empty?
  end

  def replenish_cards(deck_num)
    cards = []
    deck_num.times do
      SUITS.each do |suit|
        FACES.each do |face|
          cards << Card.new(suit, face)
        end
      end
    end
    cards.shuffle
  end
end

class Card
  attr_reader :suit, :face

  def initialize(suit, face)
    @suit = suit
    @face = face
  end

  def num_value
    return face.to_i if face.to_i != 0
    if ['J', 'Q', 'K'].include?(face)
      return 10
    else
      return 11
    end
  end
end

class Hand
  attr_reader :cards, :obtained_via_split, :stayed
  PRINT_LIMIT = 80

  def initialize(*cards)
    @cards = cards
    @stayed = false
    @obtained_via_split = false
  end

  def record_got_via_split
    @obtained_via_split = true
  end

  def busted?
    value > 21
  end

  def live?
    !@stayed && !busted? && !twenty_one?
  end

  def twenty_one?
    value == 21
  end

  def blackjack?
    twenty_one? && size == 2
  end

  def true_blackjack?(rules)
    blackjack? &&
      (rules[:post_split_blackjack] || !obtained_via_split)
  end

  def include?(card_face)
    !!cards.find { |card| card.face == card_face }
  end

  def faces
    cards.map(&:face)
  end

  def values
    cards.map(&:num_value)
  end

  def count(face)
    faces.count(face)
  end

  def soft?
    value == soft_val && include?('A')
  end

  def hard?
    !soft?
  end

  def soft_val
    cards.inject(0) { |sum, card| sum + card.num_value }
  end

  def <<(new_card)
    @cards << new_card
  end

  def stay
    @stayed = true
    self
  end

  def display_format
    arr = cards_display_array
    output = "#{arr[0]}"
    line_length = arr[0].length
    arr[1..-1].each do |str|
      if line_length + 3 + str.length > PRINT_LIMIT
        output << "\n#{str}"
        line_length = str.length
      else
        output << "   #{str}"
        line_length += (3 + str.length)
      end
    end
    output
  end

  def cards_display_array
    cards.map do |card|
      "|#{card.face} of #{card.suit}|"
    end
  end

  def display_with_hole_format
    str_1 = "|#{cards[0].face} of #{cards[0].suit}|   "
    str_2 = cards[1..-1].map do ||
      "|???? ????|"
    end.join('   ')
    str_1 + str_2
  end

  def display_upcard_format
    "|#{cards[0].face} of #{cards[0].suit}|"
  end

  def display_with_status_format(rules)
    if true_blackjack?(rules)
      return "21 (blackjack)"
    elsif twenty_one?
      return "21 (unnatural)"
    elsif busted?
      return "#{value} (bust)"
    else
      return "#{value} (stayed)"
    end
  end

  def value
    total = cards.inject(0) { |sum, card| sum + card.num_value }
    count('A').times do
      break if total <= 21
      total -= 10
    end
    total
  end

  def size
    cards.size
  end
end

class Game
  attr_reader :players, :dealer, :rules, :deck, :round
  OPTIONS = [:hit, :stay, :split]

  def initialize(rules)
    @rules = rules
    @players = setup_players
    @deck = card_supply
    @dealer = Dealer.new
    @round = 1
    @max_rounds = decide_rounds
  end

  def play
    loop do
      play_round
      break if round == @max_rounds
      update_round
    end
    goodbye_message
  end

  def play_round
    initial_deal
    if check_dealer_blackjack && rules[:dealer_wins_tie]
      dealer_blackjack_message
    else
      players.each { |player| take_turn(player) }
      dealers_turn
    end
    display_round_results
    update_player_scores
    display_player_scores
    reset_player_hands_splits_and_deck
  end

  def take_turn(player)
    check_twenty_one(player)
    while player.live_hands?
      player.hands.select(&:live?).each do |hand|
        while player.hands.include?(hand) && hand.live?
          makes_move(player, hand)
          @deck = card_supply if deck.empty?
        end
      end
    end
  end

  def dealer_hand
    dealer.hands[0]
  end

  def check_dealer_blackjack
    dealer_hand.blackjack?
  end

  def dealer_blackjack_message
    system 'clear'
    puts "Dealer got Blackjack! Better luck next time!"
    puts ''
    puts ''
    sleep 2
  end

  def check_twenty_one(player)
    initial_hand = player.hands[0]
    if initial_hand.blackjack?
      player_display(player, initial_hand)
      puts "=> Blackjack!!!"
      sleep 1
    elsif initial_hand.twenty_one?
      player_display(player, initial_hand)
      puts "=> Twenty One!"
      sleep 1
    end
  end

  def makes_move(player, hand)
    move = validate_availables(player, hand)
    case move
    when :hit
      new_hand = player.hit(hand, deck)
    when :stay
      new_hand = player.stay(hand)
    when :split
      new_hand = player.split(hand)
    end
    player_display(player, new_hand)
    unless hand.live?
      display_outcome(hand)
      sleep 1
    end
  end

  def player_display(player, hand)
    hand_idx = player.hands.index(hand)
    system 'clear'
    player_turn_header(player)
    puts "#{player.name}: Hand #{hand_idx + 1} of #{player.hands.size}"
    puts ''
    puts hand.display_format
    puts ''
    puts "=> Value: #{hand.value}"
    puts ''
  end

  def player_turn_header(player)
    puts "Round #{round} - #{player.name}'s Turn:"
    puts ''
    puts '--------------------------------------------------'
    puts "=> Dealer's Hand:   #{dealer_preturn_format}"
    puts '__________________________________________________'
  end

  def dealer_display
    system 'clear'
    dealer_turn_header
    show_player_hand_results
  end

  def dealer_turn_header
    puts "Round #{round} - Dealer's Turn:"
    puts ''
    puts "=> Dealer's Hand:"
    puts dealer_hand.display_format
    puts ''
    puts "=> Value: #{dealer_hand.value}"
    puts '__________________________________________________'
  end

  def show_player_hand_results
    players.each do |player|
      if player.hands.size > 1
        puts "#{player.name}'s Hands:"
      else
        puts "#{player.name}'s Hand:"
      end
      str = player.hands.map do |hand|
        hand.display_with_status_format(rules)
      end.join(', ')
      puts "=>  " + str
      puts ''
    end
  end

  def display_round_results
    system 'clear'
    round_result_header
    show_player_round_results
    puts 'press enter to continue'
    gets
  end

  def round_result_header
    puts "Round #{round} Results:"
    puts ''
    puts "=> Dealer's Hand:"
    puts "=> " + dealer_hand.display_with_status_format(rules)
    puts '__________________________________________________'
  end

  def show_player_round_results
    players.each do |player|
      if player.hands.size > 1
        puts "#{player.name}'s Hands:"
      else
        puts "#{player.name}'s Hand:"
      end
      str = player.hands.map do |hand|
        "#{hand.value} (#{performance_vs_dealer(hand)})"
      end.join(', ')
      puts "=>  " + str
      puts ''
    end
  end

  def dealer_preturn_format
    if rules[:deal_hole_card_after]
      dealer_hand.display_upcard_format
    else
      dealer_hand.display_with_hole_format
    end
  end

  def setup_players
    players = []
    rules[:number_of_players].times { players << Player.new }
    sleep 1
    players
  end

  def decide_rounds
    response = nil
    loop do
      system 'clear'
      puts "Welcome to Twenty One!"
      puts ''
      puts "How many rounds do you want to play?"
      response = gets.chomp
      break if response.match(/^[1-9][0-9]*$/)
      puts "Please enter a positive integer"
      sleep 1
    end
    response.to_i
  end

  def card_supply
    Deck.new(rules[:number_of_decks])
  end

  def initial_deal
    players.each do |player|
      2.times { @deck.deal(player.hands[0]) }
    end
    if rules[:deal_hole_card_after]
      @deck.deal(dealer_hand)
    else
      2.times { @deck.deal(dealer_hand) }
    end
  end

  def apply_restrictions(player, hand)
    available_options = OPTIONS.clone
    if split_restricted?(player, hand)
      available_options.delete(:split)
    end
    if hit_restricted?(hand)
      available_options.delete(:hit)
    end
    available_options
  end

  def hit_restricted?(hand)
    hand.faces[0] == 'A' &&
      hand.obtained_via_split &&
      !rules[:can_hit_split_aces]
  end

  def split_restricted?(player, hand)
    cond_1 = hand.size != 2
    cond_2 = player.splits >= rules[:split_limit]
    cond_3 = hand.values[0] != hand.values[1]
    cond_4 = rules[:rank_based_split] &&
             hand.faces[0] != hand.faces[1]
    cond_1 || cond_2 || cond_3 || cond_4
  end

  def validate_availables(player, hand)
    choice = nil
    hsh = choice_hash(player, hand)
    str = choice_str(player, hand)
    loop do
      player_display(player, hand)
      puts "Select an option:  " + str
      choice = gets.chomp
      break if hsh.keys.include?(choice)
      puts "=> Invalid entry. Please try again."
      sleep 1
    end
    hsh[choice]
  end

  def choice_hash(player, hand)
    hsh = {}
    choices = apply_restrictions(player, hand)
    k = 1
    choices.each do |option|
      hsh[k.to_s] = option
      k += 1
    end
    hsh
  end

  def choice_str(player, hand)
    hsh = choice_hash(player, hand)
    choices = apply_restrictions(player, hand)
    hsh.keys.zip(choices.map(&:to_s)).map do |arr|
      arr.join(')  ')
    end.join('    ')
  end

  def display_outcome(hand)
    if hand.busted?
      puts "=> Bust!"
    elsif true_blackjack?(hand)
      puts "=> Blackjack!"
    elsif hand.twenty_one?
      puts "=> Twenty one!"
    else
      puts "=> Stayed at #{hand.value}"
    end
  end

  def dealers_turn
    sleep 0.5
    dealer_display
    if rules[:deal_hole_card_after]
      deck.deal(dealer_hand)
      puts "=> Dealing remaining card"
      sleep 1
    end
    while dealer_hand.live?
      dealer_moves
    end
    show_dealer_behavior
  end

  def show_dealer_behavior
    dealer_display
    if dealer_hand.stayed
      puts "Dealer hand stayed at #{dealer_hand.value}"
    elsif dealer_hand.blackjack?
      puts "Dealer gets Blackjack!"
    elsif dealer_hand.twenty_one?
      puts "Dealer gets Twenty One!"
    else
      puts "Dealer busts!"
    end
    puts 'press enter to continue'
    gets
  end

  def dealer_moves
    dealer_display
    if dealer_hits?
      deck.deal(dealer_hand)
      dealer_display
      puts "Dealer hits!"
    else
      dealer_hand.stay
      dealer_display
      puts "Dealer stays!"
    end
    sleep 1
  end

  def dealer_hits?
    dealer_hand.value < 17 || (rules[:h17] &&
    dealer_hand.value == 17 && dealer_hand.soft?)
  end

  def performance_vs_dealer(hand)
    case compare_hand(hand)
    when :win then :win
    when :loss then :loss
    when :tie
      if rules[:dealer_wins_tie]
        return :loss
      else
        return :tie
      end
    end
  end

  def compare_hand(hand)
    return :loss if hand.busted?
    if rank(hand) < rank(dealer_hand)
      return :loss
    elsif rank(hand) == rank(dealer_hand)
      return :tie
    else
      return :win
    end
  end

  def rank(hand)
    if true_blackjack?(hand)
      return 22
    elsif hand.twenty_one?
      return 21
    elsif hand.busted?
      return 0
    else
      return hand.value
    end
  end

  def true_blackjack?(hand)
    hand.blackjack? &&
      (rules[:post_split_blackjack] ||
      !hand.obtained_via_split)
  end

  def update_player_scores
    players.each do |player|
      player.hands.each do |hand|
        player.score[:hands_played] += 1
        if performance_vs_dealer(hand) == :win
          player.score[:hands_won] += 1
        end
      end
    end
  end

  def display_player_scores
    system 'clear'
    player_score_header
    show_player_performances
    if round != @max_rounds
      puts 'press enter to continue'
      gets
    else
      puts ''
    end
  end

  def player_score_header
    if round == @max_rounds
      puts "Final Results:"
    else
      puts "Round #{round} Results:"
    end
    puts ''
    puts "Player Scores:"
    puts ''
    puts '__________________________________________________'
  end

  def show_player_performances
    players.each do |player|
      percentage = win_percentage(player)
      puts "#{player.name}:"
      puts "=> won #{player.score[:hands_won]} out of "\
           "#{player.score[:hands_played]} hands played."
      puts "=> (win percentage: #{percentage}%)"
      puts ''
    end
  end

  def win_percentage(player)
    player.score[:hands_won].to_f /
      player.score[:hands_played] * 100
  end

  def reset_player_hands_splits_and_deck
    players.map(&:reset_hands)
    players.map(&:reset_splits)
    dealer.reset_hands
    @deck = card_supply
  end

  def update_round
    @round += 1
  end

  def goodbye_message
    puts "Thanks for playing Twenty One! Bye!!!"
    puts ''
    puts ''
  end
end

rules = { number_of_players: 3,
          number_of_decks: 3,
          split_limit: 4,
          h17: true,
          dealer_wins_tie: true,
          can_hit_split_aces: false,
          post_split_blackjack: false,
          deal_hole_card_after: false,
          rank_based_split: false
        }

Game.new(rules).play
